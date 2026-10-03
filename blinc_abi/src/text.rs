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
    let generic = match context.generic_font {
        LayoutGeneric::Monospace => GenericFont::Monospace,
        LayoutGeneric::Serif => GenericFont::Serif,
        LayoutGeneric::SansSerif => GenericFont::SansSerif,
        _ => GenericFont::System,
    };
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
