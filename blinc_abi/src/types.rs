//! Immutable style values: brushes, colors, radii, transforms and shadows.
//!
//! Each crosses to Haxe as one `blinc_value` handle. A single type lets one
//! signal kind and one property router carry all of them; the router checks
//! that the variant suits the property.

use crate::hl::{into_handle, string_from};
use blinc_core::layer::{BlurStyle, GlassStyle, Gradient, ImageBrush, ImageFit, Point, Shadow};
use blinc_core::{Brush, Color, CornerRadius, Transform};
use hl_abi::{define_prim, vbyte};
use std::ffi::c_void;

#[derive(Clone, Default)]
pub enum Value {
    #[default]
    None,
    Brush(Brush),
    Color(Color),
    Radius(CornerRadius),
    Transform(Transform),
    Shadow(Vec<Shadow>),
}

/// `0xRRGGBB` plus a separate alpha, as the Haxe API spells colors.
fn hex_color(hex: i32, alpha: f32) -> Color {
    Color::from_hex(hex as u32).with_alpha(alpha)
}

fn value(v: Value) -> *mut c_void {
    into_handle(v)
}

// --- Brushes ---

#[unsafe(no_mangle)]
pub extern "C" fn hl_blinc_brush_solid(hex: i32, alpha: f32) -> *mut c_void {
    value(Value::Brush(Brush::Solid(hex_color(hex, alpha))))
}
define_prim!(
    hlp_blinc_brush_solid,
    hl_blinc_brush_solid,
    "Pif_Xblinc_value_"
);

#[unsafe(no_mangle)]
pub extern "C" fn hl_blinc_brush_glass(
    blur: f32,
    tint_hex: i32,
    tint_alpha: f32,
    simple: i32,
) -> *mut c_void {
    let glass = GlassStyle::new()
        .blur(blur)
        .tint(hex_color(tint_hex, tint_alpha))
        .with_simple(simple != 0);
    value(Value::Brush(Brush::Glass(glass)))
}
define_prim!(
    hlp_blinc_brush_glass,
    hl_blinc_brush_glass,
    "Pfifi_Xblinc_value_"
);

#[unsafe(no_mangle)]
pub extern "C" fn hl_blinc_brush_blur(radius: f32) -> *mut c_void {
    value(Value::Brush(Brush::Blur(BlurStyle::with_radius(radius))))
}
define_prim!(
    hlp_blinc_brush_blur,
    hl_blinc_brush_blur,
    "Pf_Xblinc_value_"
);

#[unsafe(no_mangle)]
pub unsafe extern "C" fn hl_blinc_brush_image(src: *const vbyte, fit: i32) -> *mut c_void {
    let mut img = ImageBrush::new(unsafe { string_from(src) });
    img.fit = match fit {
        1 => ImageFit::Contain,
        2 => ImageFit::Fill,
        3 => ImageFit::Tile,
        _ => ImageFit::Cover,
    };
    value(Value::Brush(Brush::Image(img)))
}
define_prim!(
    hlp_blinc_brush_image,
    hl_blinc_brush_image,
    "PBi_Xblinc_value_"
);

#[unsafe(no_mangle)]
pub extern "C" fn hl_blinc_brush_linear_gradient(
    sx: f32,
    sy: f32,
    ex: f32,
    ey: f32,
    from_hex: i32,
    from_alpha: f32,
    to_hex: i32,
    to_alpha: f32,
) -> *mut c_void {
    let grad = Gradient::linear(
        Point::new(sx, sy),
        Point::new(ex, ey),
        hex_color(from_hex, from_alpha),
        hex_color(to_hex, to_alpha),
    );
    value(Value::Brush(Brush::Gradient(grad)))
}
define_prim!(
    hlp_blinc_brush_linear_gradient,
    hl_blinc_brush_linear_gradient,
    "Pffffifif_Xblinc_value_"
);

// --- Colors ---

#[unsafe(no_mangle)]
pub extern "C" fn hl_blinc_color_hex(hex: i32, alpha: f32) -> *mut c_void {
    value(Value::Color(hex_color(hex, alpha)))
}
define_prim!(hlp_blinc_color_hex, hl_blinc_color_hex, "Pif_Xblinc_value_");

// --- Corner radius ---

#[unsafe(no_mangle)]
pub extern "C" fn hl_blinc_corner_radius(tl: f32, tr: f32, br: f32, bl: f32) -> *mut c_void {
    value(Value::Radius(CornerRadius::new(tl, tr, br, bl)))
}
define_prim!(
    hlp_blinc_corner_radius,
    hl_blinc_corner_radius,
    "Pffff_Xblinc_value_"
);

// --- Transforms ---

#[unsafe(no_mangle)]
pub extern "C" fn hl_blinc_transform_identity() -> *mut c_void {
    value(Value::Transform(Transform::identity()))
}
define_prim!(
    hlp_blinc_transform_identity,
    hl_blinc_transform_identity,
    "P_Xblinc_value_"
);

#[unsafe(no_mangle)]
pub extern "C" fn hl_blinc_transform_translate(x: f32, y: f32) -> *mut c_void {
    value(Value::Transform(Transform::translate(x, y)))
}
define_prim!(
    hlp_blinc_transform_translate,
    hl_blinc_transform_translate,
    "Pff_Xblinc_value_"
);

// --- Shadows ---

#[unsafe(no_mangle)]
pub extern "C" fn hl_blinc_shadow(
    offset_x: f32,
    offset_y: f32,
    blur: f32,
    hex: i32,
    alpha: f32,
) -> *mut c_void {
    let shadow = Shadow::new(offset_x, offset_y, blur, hex_color(hex, alpha));
    value(Value::Shadow(vec![shadow]))
}
define_prim!(hlp_blinc_shadow, hl_blinc_shadow, "Pfffif_Xblinc_value_");
