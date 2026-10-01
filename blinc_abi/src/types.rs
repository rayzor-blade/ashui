use hl_abi::{define_prim, vbyte};
use std::ffi::CStr;
use blinc_core::{Color, Brush};
use blinc_core::layer::{
    GlassStyle, BlurStyle, ImageBrush, ImageFit, Gradient, Point
};

// --- 1. Solid Brush ---
#[unsafe(no_mangle)]
pub unsafe extern "C" fn hl_blinc_brush_solid(hex: u32, alpha: f32) -> *mut Brush {
    let color = Color::from_hex(hex).with_alpha(alpha);
    Box::into_raw(Box::new(Brush::Solid(color)))
}
define_prim!(hlp_blinc_brush_solid, hl_blinc_brush_solid, "P_IF");

// --- 2. Glass Brush ---
#[unsafe(no_mangle)]
pub unsafe extern "C" fn hl_blinc_brush_glass(blur: f32, tint_hex: u32, tint_alpha: f32, simple: bool) -> *mut Brush {
    let tint = Color::from_hex(tint_hex).with_alpha(tint_alpha);
    let glass = GlassStyle::new().blur(blur).tint(tint).with_simple(simple);
    Box::into_raw(Box::new(Brush::Glass(glass)))
}
define_prim!(hlp_blinc_brush_glass, hl_blinc_brush_glass, "P_FIFB"); // Takes Float, Int, Float, Bool

// --- 3. Blur Brush (Pure backdrop blur) ---
#[unsafe(no_mangle)]
pub unsafe extern "C" fn hl_blinc_brush_blur(radius: f32) -> *mut Brush {
    let blur = BlurStyle::with_radius(radius);
    Box::into_raw(Box::new(Brush::Blur(blur)))
}
define_prim!(hlp_blinc_brush_blur, hl_blinc_brush_blur, "P_F");

// --- 4. Image Brush ---
#[unsafe(no_mangle)]
pub unsafe extern "C" fn hl_blinc_brush_image(src_bytes: *const vbyte, fit: u8) -> *mut Brush {
    let c_str = unsafe { CStr::from_ptr(src_bytes as *const i8) };
    let source = c_str.to_string_lossy().into_owned();
    
    let mut img = ImageBrush::new(source);
    img.fit = match fit {
        0 => ImageFit::Cover,
        1 => ImageFit::Contain,
        2 => ImageFit::Fill,
        3 => ImageFit::Tile,
        _ => ImageFit::Cover,
    };
    
    Box::into_raw(Box::new(Brush::Image(img)))
}
define_prim!(hlp_blinc_brush_image, hl_blinc_brush_image, "P_PI"); // Takes Pointer(Bytes), Int

// --- 5. Gradient Brush (Simple Linear) ---
#[unsafe(no_mangle)]
pub unsafe extern "C" fn hl_blinc_brush_linear_gradient(
    sx: f32, sy: f32, ex: f32, ey: f32, 
    from_hex: u32, from_alpha: f32, 
    to_hex: u32, to_alpha: f32
) -> *mut Brush {
    let start = Point::new(sx, sy);
    let end = Point::new(ex, ey);
    let from = Color::from_hex(from_hex).with_alpha(from_alpha);
    let to = Color::from_hex(to_hex).with_alpha(to_alpha);

    let grad = Gradient::linear(start, end, from, to);
    Box::into_raw(Box::new(Brush::Gradient(grad)))
}
// Returns Pointer, Takes 4xFloat(points) + Int/Float(from) + Int/Float(to)
define_prim!(hlp_blinc_brush_linear_gradient, hl_blinc_brush_linear_gradient, "P_FFFFIFIF");

// --- Drop Helper ---
#[unsafe(no_mangle)]
pub unsafe extern "C" fn hl_blinc_brush_drop(ptr: *mut Brush) {
    if !ptr.is_null() {
        unsafe { let _ = Box::from_raw(ptr); }
    }
}
define_prim!(hlp_blinc_brush_drop, hl_blinc_brush_drop, "V_P");