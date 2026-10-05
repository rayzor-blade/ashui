//! Raster images, PNG and JPEG, decoded with Blinc's `blinc_image` and kept
//! here by a slot: what ashui's `Bitmap` names. Each is drawn by resampling
//! it to the size it covers on screen, fitted to its box as CSS's
//! `object-fit` fits one, into the image atlas, as an SVG is rasterized.

use hl_abi::{define_prim, vbyte};
use std::sync::Mutex;

struct Bitmap {
    /// Straight RGBA, row by row.
    pixels: Vec<u8>,
    width: u32,
    height: u32,
}

static BITMAPS: Mutex<Vec<Option<Bitmap>>> = Mutex::new(Vec::new());

/// How an image fills a box of another shape, as ashui's `ImageFit`
/// numbers it: cropped to cover it or letterboxed whole, both centred, or
/// stretched (2, CSS's `fill`; 3, a tile, is stretched for now).
const FIT_COVER: i32 = 0;
const FIT_CONTAIN: i32 = 1;
const FIT_FILL: i32 = 2;

/// Decodes `len` bytes of PNG or JPEG; its slot, or -1 when they are not one.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn hl_blinc_bitmap_decode(bytes: *const vbyte, len: i32) -> i32 {
    if bytes.is_null() || len <= 0 {
        return -1;
    }
    let data = unsafe { std::slice::from_raw_parts(bytes as *const u8, len as usize) };
    let Ok(image) = blinc_image::DecoderRegistry::with_builtins().decode(data, None) else {
        return -1;
    };
    let mut all = BITMAPS.lock().unwrap_or_else(|e| e.into_inner());
    let bitmap = Some(Bitmap {
        pixels: image.pixels,
        width: image.width,
        height: image.height,
    });
    match all.iter().position(|b| b.is_none()) {
        Some(free) => {
            all[free] = bitmap;
            free as i32
        }
        None => {
            all.push(bitmap);
            all.len() as i32 - 1
        }
    }
}
define_prim!(hlp_blinc_bitmap_decode, hl_blinc_bitmap_decode, "Bi_i");

/// The width, or with `height` the height, of the bitmap in `slot`; 0 when there is none.
#[unsafe(no_mangle)]
pub extern "C" fn hl_blinc_bitmap_size(slot: i32, height: bool) -> i32 {
    let all = BITMAPS.lock().unwrap_or_else(|e| e.into_inner());
    all.get(slot.max(0) as usize)
        .and_then(|b| b.as_ref())
        .map_or(0, |b| if height { b.height } else { b.width } as i32)
}
define_prim!(hlp_blinc_bitmap_size, hl_blinc_bitmap_size, "ib_i");

/// Frees the bitmap in `slot`, whose slot may then name another.
#[unsafe(no_mangle)]
pub extern "C" fn hl_blinc_bitmap_release(slot: i32) {
    let mut all = BITMAPS.lock().unwrap_or_else(|e| e.into_inner());
    if let Some(b) = all.get_mut(slot.max(0) as usize) {
        *b = None;
    }
}
define_prim!(hlp_blinc_bitmap_release, hl_blinc_bitmap_release, "i_v");

/// Writes the bitmap in `slot` into `out`, `width` × `height` straight RGBA
/// pixels, fitted by `fit`. False when there is no such bitmap.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn hl_blinc_bitmap_resample(slot: i32, width: i32, height: i32, fit: i32, out: *mut vbyte) -> bool {
    if width <= 0 || height <= 0 || out.is_null() {
        return false;
    }
    let all = BITMAPS.lock().unwrap_or_else(|e| e.into_inner());
    let Some(b) = all.get(slot.max(0) as usize).and_then(|b| b.as_ref()) else {
        return false;
    };
    let out = unsafe { std::slice::from_raw_parts_mut(out as *mut u8, (width * height * 4) as usize) };
    resample(b, width as u32, height as u32, fit, out);
    true
}
define_prim!(hlp_blinc_bitmap_resample, hl_blinc_bitmap_resample, "iiiiB_b");

/// Shrinks the bitmap in `slot` so that neither side is over `max_side`,
/// keeping its shape, each side rounded to a multiple of 4 (so the texture
/// made of it can be block-compressed); its full-size pixels are freed.
/// False when there is no such bitmap or it is small enough already.
#[unsafe(no_mangle)]
pub extern "C" fn hl_blinc_bitmap_shrink(slot: i32, max_side: i32) -> bool {
    if max_side < 4 {
        return false;
    }
    let mut all = BITMAPS.lock().unwrap_or_else(|e| e.into_inner());
    let Some(b) = all.get_mut(slot.max(0) as usize).and_then(|b| b.as_mut()) else {
        return false;
    };
    let longest = b.width.max(b.height);
    if longest <= max_side as u32 {
        return false;
    }
    let scale = max_side as f32 / longest as f32;
    let side = |v: u32| ((v as f32 * scale / 4.0).round() as u32 * 4).max(4);
    let (w, h) = (side(b.width), side(b.height));
    let mut out = vec![0u8; (w * h * 4) as usize];
    resample(b, w, h, FIT_FILL, &mut out);
    *b = Bitmap { pixels: out, width: w, height: h };
    true
}
define_prim!(hlp_blinc_bitmap_shrink, hl_blinc_bitmap_shrink, "ii_b");

/// `b` fitted into `out`, `w` × `h`: the part of `b` each output pixel
/// covers averaged when shrinking, and interpolated between its four
/// nearest pixels when growing, in premultiplied colour so transparent
/// edges do not darken.
fn resample(b: &Bitmap, w: u32, h: u32, fit: i32, out: &mut [u8]) {
    out.fill(0);
    let (sw, sh) = (b.width as f32, b.height as f32);
    // The source rect drawn, and the output rect it fills.
    let (mut src, mut dst) = ([0.0, 0.0, sw, sh], [0.0, 0.0, w as f32, h as f32]);
    match fit {
        FIT_CONTAIN => {
            let s = (w as f32 / sw).min(h as f32 / sh);
            let (dw, dh) = (sw * s, sh * s);
            dst = [(w as f32 - dw) / 2.0, (h as f32 - dh) / 2.0, dw, dh];
        }
        FIT_COVER => {
            let s = (w as f32 / sw).max(h as f32 / sh);
            let (cw, ch) = (w as f32 / s, h as f32 / s);
            src = [(sw - cw) / 2.0, (sh - ch) / 2.0, cw, ch];
        }
        _ => {}
    }
    let texel = |x: u32, y: u32| -> [f32; 4] {
        let i = ((y.min(b.height - 1) * b.width + x.min(b.width - 1)) * 4) as usize;
        let a = b.pixels[i + 3] as f32 / 255.0;
        [b.pixels[i] as f32 * a, b.pixels[i + 1] as f32 * a, b.pixels[i + 2] as f32 * a, a]
    };
    let (sx, sy) = (src[2] / dst[2], src[3] / dst[3]);
    let (x0, y0) = (dst[0].floor().max(0.0) as u32, dst[1].floor().max(0.0) as u32);
    let (x1, y1) = (((dst[0] + dst[2]).ceil() as u32).min(w), ((dst[1] + dst[3]).ceil() as u32).min(h));
    for oy in y0..y1 {
        for ox in x0..x1 {
            // The output pixel's footprint in the source.
            let fx0 = src[0] + (ox as f32 - dst[0]) * sx;
            let fy0 = src[1] + (oy as f32 - dst[1]) * sy;
            let mut c = [0.0f32; 4];
            if sx > 1.0 || sy > 1.0 {
                let (ax, bx) = (fx0.floor().max(0.0) as u32, ((fx0 + sx).ceil() as u32).min(b.width));
                let (ay, by) = (fy0.floor().max(0.0) as u32, ((fy0 + sy).ceil() as u32).min(b.height));
                let mut n = 0.0;
                for y in ay..by.max(ay + 1) {
                    for x in ax..bx.max(ax + 1) {
                        let t = texel(x, y);
                        for k in 0..4 {
                            c[k] += t[k];
                        }
                        n += 1.0;
                    }
                }
                for k in 0..4 {
                    c[k] /= n;
                }
            } else {
                // The output pixel's centre, between source pixel centres.
                let (cx, cy) = (fx0 + sx * 0.5 - 0.5, fy0 + sy * 0.5 - 0.5);
                let (px, py) = (cx.floor(), cy.floor());
                let (tx, ty) = (cx - px, cy - py);
                let at = |dx: f32, dy: f32| texel((px + dx).max(0.0) as u32, (py + dy).max(0.0) as u32);
                let (a, b2, c2, d) = (at(0.0, 0.0), at(1.0, 0.0), at(0.0, 1.0), at(1.0, 1.0));
                for k in 0..4 {
                    c[k] = (a[k] * (1.0 - tx) + b2[k] * tx) * (1.0 - ty) + (c2[k] * (1.0 - tx) + d[k] * tx) * ty;
                }
            }
            let i = ((oy * w + ox) * 4) as usize;
            let a = c[3];
            for k in 0..3 {
                out[i + k] = if a > 0.0 { (c[k] / a).round().clamp(0.0, 255.0) as u8 } else { 0 };
            }
            out[i + 3] = (a * 255.0).round().clamp(0.0, 255.0) as u8;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn pair() -> Bitmap {
        Bitmap { pixels: vec![255, 0, 0, 255, 0, 0, 255, 255], width: 2, height: 1 }
    }

    #[test]
    fn contain_letterboxes() {
        let mut out = vec![0u8; 16 * 16 * 4];
        resample(&pair(), 16, 16, FIT_CONTAIN, &mut out);
        let at = |x: usize, y: usize| out[(y * 16 + x) * 4 + 3];
        assert_eq!(at(8, 1), 0, "clear above the band");
        assert_eq!(at(8, 8), 255, "the band drawn");
    }
}
