//! Glyphs for text nodes: shaped by Blinc's text engine and rasterized into
//! its glyph atlases, which ashui uploads and samples in its own text shader.
//!
//! Glyphs are rasterized at the size they cover on screen, the font size
//! times the display scale times the node's transform scale, so text stays
//! sharp when zoomed. Scales are bucketed at twelve steps per doubling, so an
//! animated zoom reuses glyphs instead of rasterizing every frame.

use blinc_layout::div::{GenericFont as LayoutGeneric, TextAlign};
use blinc_layout::tree::TextMeasureContext;
use blinc_text::{
    GenericFont, LayoutOptions, LineBreakMode, PreparedText, TextAlignment, TextAnchor,
    TextError, TextRenderer, global_font_registry,
};
use hl_abi::{define_prim, vbyte};
use std::sync::{LazyLock, Mutex, MutexGuard};

static RENDERER: LazyLock<Mutex<TextRenderer>> =
    LazyLock::new(|| Mutex::new(TextRenderer::with_shared_registry(global_font_registry())));

pub fn renderer() -> MutexGuard<'static, TextRenderer> {
    RENDERER.lock().unwrap_or_else(|e| e.into_inner())
}

/// Loads the face `context` is set in, if the renderer has not yet: layout
/// measures only with loaded faces, and estimates the rest.
pub fn ensure_face(context: &TextMeasureContext) {
    let generic = generic(context.generic_font);
    let registry = renderer().font_registry();
    let mut registry = registry.lock().unwrap_or_else(|e| e.into_inner());
    let name = context.font_name.as_deref();
    if registry
        .get_for_render_with_style(name, generic, context.font_weight, context.italic)
        .is_none()
    {
        let _ = registry.load_with_fallback_styled(name, generic, context.font_weight, context.italic);
    }
}

fn generic(g: LayoutGeneric) -> GenericFont {
    match g {
        LayoutGeneric::Monospace => GenericFont::Monospace,
        LayoutGeneric::Serif => GenericFont::Serif,
        LayoutGeneric::SansSerif => GenericFont::SansSerif,
        _ => GenericFont::System,
    }
}

/// Steps per doubling of scale that glyphs are rasterized at.
const STEPS_PER_OCTAVE: f32 = 12.0;

/// The largest size a glyph is rasterized at; beyond it glyphs are magnified.
const MAX_RASTER_SIZE: f32 = 256.0;

/// The scale `font_size` is rasterized at for `on_screen`, the device pixels
/// per layout unit: `on_screen` on its bucket, capped by `MAX_RASTER_SIZE`.
pub fn raster_scale(font_size: f32, on_screen: f32) -> f32 {
    if !(on_screen > 0.0) || !(font_size > 0.0) {
        return 1.0;
    }
    let bucket = ((on_screen.log2() * STEPS_PER_OCTAVE).round() / STEPS_PER_OCTAVE).exp2();
    bucket.min(MAX_RASTER_SIZE / font_size).max(1.0 / 64.0)
}

/// `context`'s text laid out in a box `width` wide, at `scale` times its size:
/// glyph bounds and atlas rects in raster pixels. `Err(AtlasFull)` when the
/// atlases cannot take its glyphs.
pub fn prepare(
    renderer: &mut TextRenderer,
    context: &TextMeasureContext,
    width: f32,
    align: Option<TextAlign>,
    letter_spacing: f32,
    color: [f32; 4],
    scale: f32,
) -> Result<PreparedText, TextError> {
    let options = LayoutOptions {
        // Layout rounds sizes to whole pixels, which can leave the box up to
        // half a pixel narrower than the text measured for it; the allowance
        // keeps such a line from wrapping.
        max_width: Some((width + 1.0) * scale),
        alignment: match align {
            Some(TextAlign::Center) => TextAlignment::Center,
            Some(TextAlign::Right) => TextAlignment::Right,
            _ => TextAlignment::Left,
        },
        anchor: TextAnchor::Top,
        line_break: if context.wrap {
            LineBreakMode::Word
        } else {
            LineBreakMode::None
        },
        line_height: context.line_height,
        letter_spacing: letter_spacing * scale,
    };
    let generic = generic(context.generic_font);
    renderer.prepare_text_with_style(
        &context.content,
        context.font_size * scale,
        color,
        &options,
        context.font_name.as_deref(),
        generic,
        context.font_weight,
        context.italic,
    )
}

/// How far below the top of its line box a line's glyphs start, as CSS
/// places them: half of what the line box has beyond the font's ascender
/// and descender, at `font_size`. Blinc's layout puts the first baseline at
/// the ascender, leaving all of that space below the text.
pub fn half_leading(context: &TextMeasureContext, font_size: f32) -> f32 {
    let registry = global_font_registry();
    let Ok(registry) = registry.lock() else {
        return 0.0;
    };
    let generic = match context.generic_font {
        LayoutGeneric::Monospace => GenericFont::Monospace,
        LayoutGeneric::Serif => GenericFont::Serif,
        LayoutGeneric::SansSerif => GenericFont::SansSerif,
        _ => GenericFont::System,
    };
    let Some(font) = registry.get_for_render_with_style(
        context.font_name.as_deref(),
        generic,
        context.font_weight,
        context.italic,
    ) else {
        return 0.0;
    };
    let m = font.metrics();
    let line = m.line_height_px(font_size) * context.line_height;
    (line - (m.ascender_px(font_size) - m.descender_px(font_size))) / 2.0
}

// ============================================================================
// ATLASES
// ============================================================================

/// How often each atlas changed: the coverage atlas, then the colour one.
static REVISIONS: Mutex<[i32; 2]> = Mutex::new([0, 0]);

/// The coverage atlas (`color` 0, one byte a pixel) or the colour-glyph atlas
/// (`color` 1, RGBA). Each change bumps its revision. When the revision is
/// not `seen`, writes its width, height and revision as three i32s to `info`
/// and returns its size in bytes, copying the pixels into `out` when they fit
/// in `capacity`. Returns 0 when the caller has seen this revision.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn hl_blinc_text_atlas_take(
    color: i32,
    seen: i32,
    out: *mut vbyte,
    capacity: i32,
    info: *mut vbyte,
) -> i32 {
    let mut r = renderer();
    let color = color != 0;
    let slot = color as usize;
    let mut revisions = REVISIONS.lock().unwrap_or_else(|e| e.into_inner());
    if color && r.color_atlas_is_dirty() {
        r.mark_color_atlas_clean();
        revisions[slot] += 1;
    } else if !color && r.atlas_is_dirty() {
        r.mark_atlas_clean();
        revisions[slot] += 1;
    }
    let revision = revisions[slot];
    if revision == seen {
        return 0;
    }
    let ((w, h), pixels) = if color {
        (r.color_atlas_dimensions(), r.color_atlas_pixels())
    } else {
        (r.atlas_dimensions(), r.atlas_pixels())
    };
    if !info.is_null() {
        let info = info as *mut i32;
        unsafe {
            info.write_unaligned(w as i32);
            info.add(1).write_unaligned(h as i32);
            info.add(2).write_unaligned(revision);
        }
    }
    let size = pixels.len();
    if !out.is_null() && size <= capacity.max(0) as usize {
        unsafe { std::ptr::copy_nonoverlapping(pixels.as_ptr(), out as *mut u8, size) };
    }
    size as i32
}
define_prim!(
    hlp_blinc_text_atlas_take,
    hl_blinc_text_atlas_take,
    "PiiBiB_i"
);

// ============================================================================
// CARETS
// ============================================================================

/// Where a caret can stand in `text`, set in text node `node`'s font and
/// letter spacing at `font_size` (the node's own when 0): for each character
/// boundary, its index in the string as UTF-16 (Haxe's indexing), its x and
/// its line, as three f32s in `out`, at most `capacity` of them. With
/// `wrap_width` above 0, lines wrap at that width, the width the node is laid
/// out at, with the allowance the renderer gives it.
/// A line break ends a line; a blank line still has a stop. Writes the line
/// height and the number of lines as two f32s to `info`. Returns how many
/// stops there are; 0 when the node is not text or its font is not loaded.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn hl_blinc_text_carets(
    h: *mut std::ffi::c_void,
    node: u64,
    text: *const vbyte,
    font_size: f32,
    wrap_width: f32,
    out: *mut vbyte,
    capacity: i32,
    info: *mut vbyte,
) -> i32 {
    let Some(tree) = (unsafe { crate::node::tree(h) }) else {
        return 0;
    };
    let id = blinc_layout::tree::LayoutNodeId::from_raw(node);
    let Some(context) = tree.layout.text_context(id) else {
        return 0;
    };
    let text = unsafe { crate::hl::string_from(text) };
    let letter_spacing = tree
        .props
        .get(&id)
        .and_then(|p| p.letter_spacing)
        .unwrap_or(0.0);
    // The renderer wraps at the laid-out width plus its allowance for rounding.
    let max_width = (wrap_width > 0.0).then_some(wrap_width + 1.0);
    let generic = match context.generic_font {
        LayoutGeneric::Monospace => GenericFont::Monospace,
        LayoutGeneric::Serif => GenericFont::Serif,
        LayoutGeneric::SansSerif => GenericFont::SansSerif,
        _ => GenericFont::System,
    };
    let font = {
        let registry = global_font_registry();
        let Ok(mut registry) = registry.lock() else {
            return 0;
        };
        match registry.get_for_render_with_style(
            context.font_name.as_deref(),
            generic,
            context.font_weight,
            context.italic,
        ) {
            Some(font) => font,
            None => match registry.load_generic(generic) {
                Ok(font) => font,
                Err(_) => return 0,
            },
        }
    };
    let size = if font_size > 0.0 { font_size } else { context.font_size };
    let options = LayoutOptions {
        max_width,
        alignment: TextAlignment::Left,
        anchor: TextAnchor::Top,
        line_break: if max_width.is_some() {
            LineBreakMode::Word
        } else {
            LineBreakMode::None
        },
        line_height: context.line_height,
        letter_spacing,
    };
    let line_height = font.metrics().line_height_px(size) * context.line_height;
    // UTF-16 index of every byte offset that starts a character.
    let mut utf16 = vec![0u32; text.len() + 1];
    let mut units = 0u32;
    for (byte, ch) in text.char_indices() {
        utf16[byte] = units;
        units += ch.len_utf16() as u32;
    }
    utf16[text.len()] = units;
    // Each paragraph between line breaks is laid out on its own, as the
    // renderer breaks lines at them; an empty one is still a line.
    let engine = blinc_text::TextLayoutEngine::new();
    let mut carets: Vec<[f32; 3]> = Vec::new();
    let mut line = 0usize;
    let mut base = 0usize;
    for paragraph in text.split('\n') {
        let layout = engine.layout(paragraph, &font, size, &options);
        if layout.lines.is_empty() {
            carets.push([utf16[base] as f32, 0.0, line as f32]);
            line += 1;
        }
        for (i, l) in layout.lines.iter().enumerate() {
            for g in &l.glyphs {
                let index = utf16[(base + g.byte_offset).min(text.len())] as f32;
                if carets.last().is_none_or(|c| c[0] != index) {
                    carets.push([index, g.x, line as f32]);
                }
            }
            // The paragraph's end: before its line break, or the text's end.
            if i + 1 == layout.lines.len() {
                let end = utf16[base + paragraph.len()] as f32;
                if carets.last().is_none_or(|c| c[0] != end) {
                    carets.push([end, l.width, line as f32]);
                }
            }
            line += 1;
        }
        base += paragraph.len() + 1;
    }
    if !info.is_null() {
        let info = info as *mut f32;
        unsafe {
            info.write_unaligned(line_height);
            info.add(1).write_unaligned(line.max(1) as f32);
        }
    }
    if !out.is_null() {
        let out = out as *mut f32;
        for (i, c) in carets.iter().take(capacity.max(0) as usize).enumerate() {
            for (j, v) in c.iter().enumerate() {
                unsafe { out.add(i * 3 + j).write_unaligned(*v) };
            }
        }
    }
    carets.len() as i32
}
define_prim!(
    hlp_blinc_text_carets,
    hl_blinc_text_carets,
    "PXblinc_tree_lBffBiB_i"
);

#[cfg(test)]
mod tests {
    use super::*;
    use blinc_layout::text_measure::{TextLayoutOptions, measure_text_with_options};

    /// Layout measures text as wide as it is drawn, so a word laid out on one
    /// line is not broken when drawn: regular and bold alike.
    #[test]
    fn layout_measures_text_as_drawn() {
        blinc_layout::init_text_measurer_with_registry(renderer().font_registry());
        let options = LayoutOptions {
            max_width: None,
            alignment: TextAlignment::Left,
            anchor: TextAnchor::Top,
            line_break: LineBreakMode::None,
            line_height: 1.2,
            letter_spacing: 0.0,
        };
        for weight in [400u16, 700] {
            ensure_face(&TextMeasureContext {
                content: "Card".into(),
                font_size: 12.0,
                line_height: 1.2,
                wrap: false,
                font_name: None,
                generic_font: LayoutGeneric::System,
                font_weight: weight,
                italic: false,
            });
            let mut measure = TextLayoutOptions::new();
            measure.font_weight = weight;
            let measured = measure_text_with_options("Card", 12.0, &measure).width;
            let drawn = renderer()
                .prepare_text_with_style("Card", 12.0, [1.0; 4], &options, None, GenericFont::System, weight, false)
                .unwrap()
                .width;
            assert!((measured - drawn).abs() < 0.01, "weight {weight}: measured {measured}, drawn {drawn}");
        }
    }
}
