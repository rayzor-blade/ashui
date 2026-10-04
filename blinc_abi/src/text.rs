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
    GenericFont, LayoutOptions, LineBreakMode, PreparedText, SubpixelX, TextAlignment,
    TextAnchor, TextError, TextRenderer, global_font_registry,
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

/// The faces `system-ui` names, by platform, as browsers resolve it. On
/// macOS that is SF Pro, a variable font whose weights the text renderer
/// cannot set yet, so Helvetica Neue, whose static weights and metrics
/// centre capitals as SF Pro's do, stands in for it.
#[cfg(target_os = "macos")]
const SYSTEM_UI: &[&str] = &["Helvetica Neue"];
#[cfg(target_os = "windows")]
const SYSTEM_UI: &[&str] = &["Segoe UI Variable", "Segoe UI"];
#[cfg(not(any(target_os = "macos", target_os = "windows")))]
const SYSTEM_UI: &[&str] = &[];

/// A CSS font stack resolved as a browser does: the first family installed,
/// or the first generic keyword (`monospace`, `serif`, `sans-serif`,
/// `system-ui` and kin) as Blinc's generic face, `system-ui` as the
/// platform's UI face where it is installed. `ui-monospace`,
/// `ui-serif` and `ui-sans-serif` name the platform's own face, which the
/// families after them usually list, so they are used only if none of
/// those is installed. A stack with none is the system face.
pub fn resolve_family(stack: &str) -> (Option<String>, LayoutGeneric) {
    let registry = renderer().font_registry();
    let mut registry = registry.lock().unwrap_or_else(|e| e.into_inner());
    let mut platform = None;
    for name in stack.split(',') {
        let name = name.trim().trim_matches(|c| c == '"' || c == '\'');
        let generic = match name.to_ascii_lowercase().as_str() {
            "" => continue,
            "ui-monospace" => {
                platform.get_or_insert(LayoutGeneric::Monospace);
                continue;
            }
            "ui-serif" => {
                platform.get_or_insert(LayoutGeneric::Serif);
                continue;
            }
            "ui-sans-serif" => {
                platform.get_or_insert(LayoutGeneric::SansSerif);
                continue;
            }
            "monospace" => Some(LayoutGeneric::Monospace),
            "serif" => Some(LayoutGeneric::Serif),
            "sans-serif" => Some(LayoutGeneric::SansSerif),
            "system-ui" | "-apple-system" | "blinkmacsystemfont" => Some(LayoutGeneric::System),
            _ => None,
        };
        if let Some(g) = generic {
            // The platform's UI face for system-ui, as a browser's: its metrics, not a generic sans-serif's, centre capitals in their line.
            if g == LayoutGeneric::System && platform.is_none() {
                drop(registry);
                return (system_ui(), LayoutGeneric::System);
            }
            return (None, platform.unwrap_or(g));
        }
        if registry.has_font(name) {
            return (Some(name.to_string()), LayoutGeneric::System);
        }
    }
    match platform {
        Some(p) => (None, p),
        None => {
            drop(registry);
            (system_ui(), LayoutGeneric::System)
        }
    }
}

/// The installed face of `SYSTEM_UI`, looked up once: what text with no family of its own is set in.
pub fn system_ui() -> Option<String> {
    static FACE: std::sync::OnceLock<Option<String>> = std::sync::OnceLock::new();
    FACE.get_or_init(|| {
        let registry = renderer().font_registry();
        let mut registry = registry.lock().unwrap_or_else(|e| e.into_inner());
        SYSTEM_UI.iter().find(|f| registry.has_font(f)).map(|f| f.to_string())
    })
    .clone()
}

fn generic(g: LayoutGeneric) -> GenericFont {
    match g {
        LayoutGeneric::Monospace => GenericFont::Monospace,
        LayoutGeneric::Serif => GenericFont::Serif,
        LayoutGeneric::SansSerif => GenericFont::SansSerif,
        _ => GenericFont::System,
    }
}

/// The offsets within a pixel a glyph may be rasterized at: thirds.
pub const SUBPIXEL_PHASES: std::num::NonZeroU8 = std::num::NonZeroU8::new(3).unwrap();

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
/// glyph bounds and atlas rects in raster pixels. With `subpixel`, each glyph
/// is on the whole pixel Blinc chose for it, from the run's origin snapped down,
/// its fraction rasterized into it. `Err(AtlasFull)` when the atlases cannot
/// take its glyphs.
#[allow(clippy::too_many_arguments)]
pub fn prepare(
    renderer: &mut TextRenderer,
    context: &TextMeasureContext,
    width: f32,
    align: Option<TextAlign>,
    letter_spacing: f32,
    color: [f32; 4],
    scale: f32,
    subpixel: Option<SubpixelX>,
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
    renderer.prepare_text_subpixel(
        &context.content,
        context.font_size * scale,
        color,
        &options,
        context.font_name.as_deref(),
        generic,
        context.font_weight,
        context.italic,
        subpixel,
    )
}

/// How far below the top of its line box a line's glyphs start, as CSS
/// places them: half of what the line box has beyond the font's ascender
/// and descender, at `font_size`. Blinc's layout puts the first baseline at
/// the ascender, leaving all of that space below the text.
/// CSS's `line-height`, a multiple of the font size, as a multiple of the
/// face's own line height (ascent, descent and gap), which is how Blinc's
/// measure and renderer read a context's: so a line is `font_size * css`
/// tall whatever the face, as in CSS.
pub fn face_line_height(context: &TextMeasureContext, css: f32) -> f32 {
    let registry = global_font_registry();
    let Ok(registry) = registry.lock() else {
        return css;
    };
    let Some(font) = registry.get_for_render_with_style(
        context.font_name.as_deref(),
        generic(context.generic_font),
        context.font_weight,
        context.italic,
    ) else {
        return css;
    };
    let natural = font.metrics().line_height_px(1.0);
    if natural > 0.0 { css / natural } else { css }
}

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

/// The changes an atlas has had, newest last, each with the region it wrote
/// and the atlas's size then; enough of them for a caller a few frames behind.
struct AtlasHistory {
    revision: i32,
    changes: std::collections::VecDeque<(i32, (u32, u32, u32, u32), (u32, u32))>,
}

/// How many changes an atlas remembers; a caller further behind takes it whole.
const ATLAS_HISTORY: usize = 32;

/// The coverage atlas's history, then the colour one's.
static HISTORIES: Mutex<[AtlasHistory; 2]> = Mutex::new([
    AtlasHistory { revision: 0, changes: std::collections::VecDeque::new() },
    AtlasHistory { revision: 0, changes: std::collections::VecDeque::new() },
]);

/// The coverage atlas (`color` 0, one byte a pixel) or the colour-glyph atlas
/// (`color` 1, RGBA). Each change bumps its revision. When the revision is
/// not `seen`, writes seven i32s to `info`: the atlas's width, height and
/// revision, then the region `x`, `y`, `width` and `height` changed since
/// `seen`, the whole atlas when `seen` is 0, too old, or older than its last
/// growth. Returns the region's size in bytes, copying its rows, packed, into
/// `out` when they fit in `capacity`. Returns 0 when the caller has seen this
/// revision.
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
    let mut histories = HISTORIES.lock().unwrap_or_else(|e| e.into_inner());
    let history = &mut histories[color as usize];
    let (dirty, rect, dims) = if color {
        (r.color_atlas_is_dirty(), r.color_atlas_dirty_rect(), r.color_atlas_dimensions())
    } else {
        (r.atlas_is_dirty(), r.atlas_dirty_rect(), r.atlas_dimensions())
    };
    if dirty {
        if color { r.mark_color_atlas_clean() } else { r.mark_atlas_clean() }
        history.revision += 1;
        history.changes.push_back((history.revision, rect.unwrap_or((0, 0, dims.0, dims.1)), dims));
        if history.changes.len() > ATLAS_HISTORY {
            history.changes.pop_front();
        }
    }
    let revision = history.revision;
    if revision == seen {
        return 0;
    }
    // The union of what changed after `seen`, when every change since is remembered and the atlas kept its size.
    let since: Vec<_> = history.changes.iter().filter(|c| c.0 > seen).collect();
    let known = seen > 0 && since.first().is_some_and(|c| c.0 == seen + 1) && since.iter().all(|c| c.2 == dims);
    let (x, y, w, h) = if known {
        let (mut x0, mut y0, mut x1, mut y1) = (u32::MAX, u32::MAX, 0, 0);
        for &&(_, (x, y, w, h), _) in &since {
            x0 = x0.min(x);
            y0 = y0.min(y);
            x1 = x1.max(x + w);
            y1 = y1.max(y + h);
        }
        (x0, y0, x1.min(dims.0) - x0, y1.min(dims.1) - y0)
    } else {
        (0, 0, dims.0, dims.1)
    };
    if !info.is_null() {
        let info = info as *mut i32;
        for (i, v) in [dims.0 as i32, dims.1 as i32, revision, x as i32, y as i32, w as i32, h as i32].into_iter().enumerate() {
            unsafe { info.add(i).write_unaligned(v) };
        }
    }
    let bpp = if color { 4 } else { 1 };
    let row = w as usize * bpp;
    let size = row * h as usize;
    if !out.is_null() && size <= capacity.max(0) as usize {
        let pixels = if color { r.color_atlas_pixels() } else { r.atlas_pixels() };
        let stride = dims.0 as usize * bpp;
        for j in 0..h as usize {
            let from = (y as usize + j) * stride + x as usize * bpp;
            unsafe { std::ptr::copy_nonoverlapping(pixels[from..from + row].as_ptr(), (out as *mut u8).add(j * row), row) };
        }
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
/// height, the number of lines, and the font's ascender and descender (below
/// the baseline, so negative) at that size as four f32s to `info`. Returns how many
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
        let m = font.metrics();
        unsafe {
            info.write_unaligned(line_height);
            info.add(1).write_unaligned(line.max(1) as f32);
            info.add(2).write_unaligned(m.ascender_px(size));
            info.add(3).write_unaligned(m.descender_px(size));
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
                letter_spacing: 0.0,
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

// ============================================================================
// OUTLINES
// ============================================================================

/// Path commands for a glyph outline, in pixels, the baseline at y 0 and y
/// growing down: 0 move (x, y), 1 line (x, y), 2 quadratic (cx, cy, x, y),
/// 3 cubic (c1x, c1y, c2x, c2y, x, y), 4 close.
struct Outline {
    out: Vec<f32>,
    scale: f32,
    x: f32,
    y: f32,
}

impl ttf_parser::OutlineBuilder for Outline {
    fn move_to(&mut self, x: f32, y: f32) {
        self.out.extend([0.0, self.x + x * self.scale, self.y - y * self.scale]);
    }
    fn line_to(&mut self, x: f32, y: f32) {
        self.out.extend([1.0, self.x + x * self.scale, self.y - y * self.scale]);
    }
    fn quad_to(&mut self, x1: f32, y1: f32, x: f32, y: f32) {
        let s = self.scale;
        self.out.extend([2.0, self.x + x1 * s, self.y - y1 * s, self.x + x * s, self.y - y * s]);
    }
    fn curve_to(&mut self, x1: f32, y1: f32, x2: f32, y2: f32, x: f32, y: f32) {
        let s = self.scale;
        self.out.extend([3.0, self.x + x1 * s, self.y - y1 * s, self.x + x2 * s, self.y - y2 * s, self.x + x * s, self.y - y * s]);
    }
    fn close(&mut self) {
        self.out.push(4.0);
    }
}

/// `text` laid out in a face of `font_name` (else the generic family), as
/// `style` sets it, six f32s: generic family (0 system, 1 monospace, 2
/// serif, 3 sans-serif), weight, italic (0 or 1), size in pixels, letter
/// spacing and line height; as path commands (see `Outline`) of every
/// glyph: the first line's baseline at y 0, each line after it `line_height`
/// times the face's line below. Writes the widest line's width, the face's
/// ascent and descent (positive, below the baseline) and its line height,
/// in pixels, as four f32s to `info`. Returns the number of f32s, copying
/// them to `out` when they fit in `capacity`; 0 when no face is found.
#[unsafe(no_mangle)]
#[allow(clippy::too_many_arguments)]
pub unsafe extern "C" fn hl_blinc_text_outline(
    text: *const vbyte,
    font_name: *const vbyte,
    style: *const vbyte,
    out: *mut vbyte,
    capacity: i32,
    info: *mut vbyte,
) -> i32 {
    if style.is_null() {
        return 0;
    }
    let s = |i: usize| unsafe { (style as *const f32).add(i).read_unaligned() };
    let (generic, weight, italic, size, letter_spacing, line_height) = (s(0) as i32, s(1) as i32, s(2) != 0.0, s(3), s(4), s(5));
    let text = unsafe { crate::hl::string_from(text) };
    let name = unsafe { crate::hl::opt_string_from(font_name) };
    let generic = match generic {
        1 => GenericFont::Monospace,
        2 => GenericFont::Serif,
        3 => GenericFont::SansSerif,
        _ => GenericFont::System,
    };
    // Resolved before the registry is locked: finding the system face locks it too.
    let name = name.or_else(|| if generic == GenericFont::System { system_ui() } else { None });
    // From the renderer's registry, loaded as text nodes' faces are, so a weight not yet used is found.
    let font = {
        let registry = renderer().font_registry();
        let mut registry = registry.lock().unwrap_or_else(|e| e.into_inner());
        let weight = weight.clamp(1, 1000) as u16;
        match registry.get_for_render_with_style(name.as_deref(), generic, weight, italic) {
            Some(font) => font,
            None => match registry.load_with_fallback_styled(name.as_deref(), generic, weight, italic) {
                Ok(font) => font,
                Err(_) => return 0,
            },
        }
    };
    let Ok(face) = ttf_parser::Face::parse(font.data(), font.face_index()) else {
        return 0;
    };
    let scale = size / face.units_per_em() as f32;
    let metrics = font.metrics();
    let ascent = metrics.ascender_px(size);
    let descent = -metrics.descender_px(size);
    let natural = metrics.line_height_px(size);
    let options = LayoutOptions {
        max_width: None,
        alignment: TextAlignment::Left,
        anchor: TextAnchor::Top,
        line_break: LineBreakMode::None,
        line_height: 1.0,
        letter_spacing,
    };
    let engine = blinc_text::TextLayoutEngine::new();
    let mut outline = Outline { out: Vec::new(), scale, x: 0.0, y: 0.0 };
    let mut widest = 0.0f32;
    for (row, paragraph) in text.split('\n').enumerate() {
        let layout = engine.layout(paragraph, &font, size, &options);
        widest = widest.max(layout.width);
        let down = row as f32 * natural * line_height;
        for line in &layout.lines {
            for g in &line.glyphs {
                // A glyph the face lacks draws nothing rather than its missing-glyph box.
                if g.glyph_id == 0 {
                    continue;
                }
                outline.x = g.x;
                outline.y = down + (g.y - line.baseline_y);
                face.outline_glyph(ttf_parser::GlyphId(g.glyph_id), &mut outline);
            }
        }
    }
    if !info.is_null() {
        let info = info as *mut f32;
        for (i, v) in [widest, ascent, descent, natural].into_iter().enumerate() {
            unsafe { info.add(i).write_unaligned(v) };
        }
    }
    let n = outline.out.len();
    if !out.is_null() && n <= capacity.max(0) as usize {
        unsafe { std::ptr::copy_nonoverlapping(outline.out.as_ptr(), out as *mut f32, n) };
    }
    n as i32
}
define_prim!(
    hlp_blinc_text_outline,
    hl_blinc_text_outline,
    "PBBBBiB_i"
);
