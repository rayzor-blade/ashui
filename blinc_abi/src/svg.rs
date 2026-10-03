//! SVG rasterization, for ashui's SVG elements: ashui parses and checks the
//! markup itself and hands Blinc only what to rasterize, at the size it
//! covers on screen.

use crate::hl::string_from;
use blinc_svg::RasterizedSvg;
use hl_abi::{define_prim, vbyte};

/// Rasterizes `markup` into `width` × `height` straight-alpha RGBA pixels in
/// `out`, which holds at least `width * height * 4` bytes, its viewBox fitted
/// and centred. False when the markup does not parse.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn hl_blinc_svg_rasterize(
    markup: *const vbyte,
    width: i32,
    height: i32,
    out: *mut vbyte,
) -> bool {
    if width <= 0 || height <= 0 || out.is_null() {
        return false;
    }
    let markup = unsafe { string_from(markup) };
    let Ok(raster) = RasterizedSvg::from_str(&markup, width as u32, height as u32) else {
        return false;
    };
    let size = (width * height * 4) as usize;
    if raster.pixels.len() != size {
        return false;
    }
    unsafe { std::ptr::copy_nonoverlapping(raster.pixels.as_ptr(), out as *mut u8, size) };
    true
}
define_prim!(
    hlp_blinc_svg_rasterize,
    hl_blinc_svg_rasterize,
    "PBiiB_b"
);
