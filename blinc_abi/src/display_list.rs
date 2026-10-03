//! The laid-out tree as a flat list of primitives to draw, packed for the
//! GPU: one record of [`RECORD_FLOATS`] f32s per primitive, in paint order,
//! which the UI shaders read as rows of a float texture.
//!
//! A record is the subset of Blinc's `GpuPrimitive` (blinc_gpu/primitives.rs)
//! that a box needs, field for field, so ashui's shaders are ports of
//! Blinc's `sdf_core` and `sdf_shadow`. Each row is a vec4:
//!
//! | 0  | the box's top-left on screen after transforms, width, height   |
//! | 1  | corner radii: top-left, top-right, bottom-right, bottom-left   |
//! | 2  | fill colour, or gradient start; straight alpha, opacity applied |
//! | 3  | gradient end colour                                            |
//! | 4  | border widths: top, right, bottom, left, each its own           |
//! | 5  | border colour, opacity applied                                 |
//! | 6  | shadow offset x, offset y, blur, spread; or a local clip rect   |
//! | 7  | shadow colour, opacity applied; or the local clip's radii       |
//! | 8  | clip bounds x, y, width, height                                |
//! | 9  | clip corner radii                                              |
//! | 10 | gradient: linear x1, y1, x2, y2 or radial cx, cy, r, 0, in pixels from the box's top-left |
//! | 11 | primitive type, fill type, clips, the clips' corner `n`         |
//! | 12 | corner shape `n`, theme applied: top-left, top-right, bottom-right, bottom-left |
//! | 13 | gradient middle stop colour, opacity applied                   |
//! | 14 | gradient stop offsets: first, middle, last; 1 if there is a middle |
//! | 15 | a, b, c, d: a point `(x, y)` from the box's top-left is at       |
//! |    | `(a·x + c·y, b·x + d·y)` from its screen top-left                |
//! | 16-19 | each side's border colour, top, right, bottom, left, opacity applied |
//! | 20 | the on-screen rect of the innermost clip that fades its overflow |
//! | 21 | that clip's fade distances: top, right, bottom, left; 0 is none |
//! | 22 | the innermost `clip-path`'s frame: a, b, c, d of the inverse of   |
//! |    | its element's transform, taking a screen point to that element  |
//! | 23 | that inverse's e and f, less the element's origin; the shape:   |
//! |    | 0 none, 1 ellipse, 2 rounded rect, 3 polygon; the rect's radius |
//! | 24 | the shape in the element's coordinates: ellipse cx, cy, rx, ry, |
//! |    | rect x, y, width, height, or a polygon's first texel and point   |
//! |    | count in the points after the records                           |
//!
//! After the records, in whole records' room, come the points of polygon
//! clips, two to a row; see `Glyphs::points`.
//!
//! A text node adds one record per glyph, a `PRIM_TEXT` quad whose bounds
//! are the glyph's, whose colour is the text's, whose gradient row is the
//! glyph's rect in its atlas in pixels, and whose fill type is 1 when that
//! is the colour-glyph atlas (see `text`).
//!
//! A node with an image adds a `PRIM_IMAGE` record over its content box,
//! coloured with its text colour, own or inherited, which an SVG's
//! `currentColor` takes, and
//! with its opacity in `color2.a`. Its gradient row holds the image's slot
//! and the device pixels per unit it covers on screen; the caller replaces
//! them with the image's rect in its atlas.
//!
//! The walk follows Blinc's `paint/basic.rs`: a node's shadows, last first,
//! then its fill merged with its border, then its outline, then its
//! children under the clip it pushes when its overflow is not visible,
//! which follows its corner shape.
//! A node that clips draws its border after its children instead, so they
//! cannot cover it where the curves differ. Glass and blur brushes draw a
//! backdrop record: what is behind the box, blurred and colour-filtered.
//! A node's 2D transform applies about its centre, after its ancestors'.
//!
//! A record has up to two clips, each rounded: one in screen space, rows 8
//! and 9, and one in the record's own coordinates, rows 6 and 7, which only
//! shadows do not have. A clip pushed under the same transform as the
//! record is exact in its own coordinates, so a turned card clips its
//! children to its turned, rounded box; any other clip under a transform is
//! its bounding box on screen. The clips field is 1 for the screen clip
//! plus 2 for the local one. The
//! corner shape is the node's own; ashui applies its theme's squircle to it
//! after the walk.

use crate::node::Tree;
use crate::text;
use blinc_core::{Brush, Color, CornerRadius, Gradient, GradientSpace, Transform};
use blinc_layout::element::RenderProps;
use blinc_layout::tree::LayoutNodeId;
use blinc_text::{TextError, TextRenderer};
use taffy::Overflow;

pub const RECORD_FLOATS: usize = 100;

/// `type_info.x`, as Blinc's `PrimitiveType`.
pub const PRIM_RECT: f32 = 0.0;
pub const PRIM_SHADOW: f32 = 3.0;
pub const PRIM_TEXT: f32 = 7.0;
/// ashui's own: Blinc draws images in a pass of their own.
pub const PRIM_IMAGE: f32 = 32.0;
/// The records after it, up to its `PRIM_LAYER`, are drawn into a layer of
/// their own: a group with opacity, as CSS composites one.
pub const PRIM_LAYER_BEGIN: f32 = 40.0;
/// Draws the layer the last `PRIM_LAYER_BEGIN` began over its bounds, its
/// alpha times `color.a`, its colour through the colour filter in rows 3 to
/// 5 (see `filter_matrix`), blurred by a Gaussian of `color.r` pixels, over
/// its drop shadow: offset by `gradient.xy` pixels, of `gradient.z` pixels'
/// deviation, in the colour `via`.
pub const PRIM_LAYER: f32 = 41.0;
/// What is drawn behind its box, blurred by `color.x` target pixels of
/// deviation and filtered by the matrix in `color2`, `border` and
/// `border_color`, drawn back over the box before the rest of its node;
/// `color.y` is how far past the box the blur reads, in layout units.
pub const PRIM_BACKDROP: f32 = 42.0;

/// `type_info.y`, as Blinc's `FillType`.
const FILL_SOLID: f32 = 0.0;
const FILL_LINEAR: f32 = 1.0;
const FILL_RADIAL: f32 = 2.0;

/// `type_info.z`, as Blinc's `ClipType`.
const CLIP_NONE: f32 = 0.0;
const CLIP_RECT: f32 = 1.0;

/// Blinc's bounds for "no clip".
const NO_CLIP: [f32; 4] = [-10000.0, -10000.0, 100000.0, 100000.0];

/// A 2D affine `[a, b, c, d, tx, ty]`: `x' = a·x + c·y + tx`, `y' = b·x + d·y + ty`.
pub type Affine = [f32; 6];

pub const IDENTITY: Affine = [1.0, 0.0, 0.0, 1.0, 0.0, 0.0];

/// `outer` after `inner`: the point goes through `inner` first.
pub(crate) fn compose(outer: Affine, inner: Affine) -> Affine {
    let [a, b, c, d, e, f] = outer;
    let [a2, b2, c2, d2, e2, f2] = inner;
    [
        a * a2 + c * b2,
        b * a2 + d * b2,
        a * c2 + c * d2,
        b * c2 + d * d2,
        a * e2 + c * f2 + e,
        b * e2 + d * f2 + f,
    ]
}

pub(crate) fn apply(m: Affine, x: f32, y: f32) -> (f32, f32) {
    (m[0] * x + m[2] * y + m[4], m[1] * x + m[3] * y + m[5])
}

/// The axis-aligned box around `rect` after `m`.
fn bounding(m: Affine, rect: [f32; 4]) -> [f32; 4] {
    let [x, y, w, h] = rect;
    let corners = [
        apply(m, x, y),
        apply(m, x + w, y),
        apply(m, x, y + h),
        apply(m, x + w, y + h),
    ];
    let (mut x0, mut y0, mut x1, mut y1) = (f32::MAX, f32::MAX, f32::MIN, f32::MIN);
    for (cx, cy) in corners {
        x0 = x0.min(cx);
        y0 = y0.min(cy);
        x1 = x1.max(cx);
        y1 = y1.max(cy);
    }
    [x0, y0, x1 - x0, y1 - y0]
}

/// What text drawing needs on the walk: the text engine, the device pixels
/// per layout unit, and whether a node's glyphs did not fit the atlases.
pub struct Glyphs<'a> {
    pub renderer: &'a mut TextRenderer,
    pub display_scale: f32,
    pub atlas_full: bool,
    pub shapes: Shapes,
    /// Polygon clips' points, x and y, each polygon from a row's start; a
    /// record's offset into them counts rows from their start until the
    /// list is packed (see `node::hl_blinc_tree_display_list`).
    pub points: Vec<f32>,
}

pub const SHAPE_POLYGON: f32 = 3.0;

/// The installed theme's corner smoothing, as ashui's theme decides it: the
/// squircle `n` (0 when smoothing is off), the radius below which corners
/// stay round, and the theme's full radius.
#[derive(Clone, Copy)]
pub struct Shapes {
    pub n: f32,
    pub threshold: f32,
    pub radius_full: f32,
}

impl Shapes {
    /// The corner shape to draw a box with, as Blinc's paint walk decides it.
    /// An explicit shape, or a locked one, wins. Otherwise smoothing gives
    /// each corner the theme's `n`, except corners under the threshold,
    /// corners near a full circle (at least 99% of the full radius or 90% of
    /// half the shorter side) and pills, which stay round so they do not
    /// wobble.
    fn resolve(&self, explicit: [f32; 4], radii: [f32; 4], w: f32, h: f32, locked: bool) -> [f32; 4] {
        let round = explicit.iter().all(|n| (n - 1.0).abs() < 0.001);
        if locked || !round {
            return explicit;
        }
        if self.n <= 0.0 {
            return [1.0; 4];
        }
        let half_short = w.min(h) * 0.5;
        if half_short > 0.0 && radii.iter().all(|&r| r >= half_short - 0.5) {
            return [1.0; 4];
        }
        let full = self.radius_full * 0.99;
        let near = half_short * 0.90;
        radii.map(|r| {
            if r >= full || r >= near || r < self.threshold {
                1.0
            } else {
                self.n
            }
        })
    }
}

/// A clip a node pushes for its children: on screen, `rect` rounded by
/// `radii`; in layout coordinates under the transform `frame`, `layout`
/// rounded by `layout_radii`.
#[derive(Clone, Copy)]
pub struct Clip {
    rect: [f32; 4],
    radii: [f32; 4],
    layout: [f32; 4],
    layout_radii: [f32; 4],
    frame: Affine,
    /// The corner `n` of the node that pushed it, so a squircle parent clips
    /// its children to the same curve it is drawn with.
    n: f32,
    /// How far in from each edge, top, right, bottom, left, what it clips
    /// fades out; zeros for none.
    fade: [f32; 4],
    /// A `clip-path` instead of a rect: it clips by its shape alone.
    shape: Option<ShapeClip>,
}

/// A `clip-path` resolved against its element's box, as the shaders read
/// it: rows 22 to 24 of a record.
#[derive(Clone, Copy)]
struct ShapeClip {
    inverse: [f32; 4],
    rest: [f32; 4],
    params: [f32; 4],
}

const SHAPE_ELLIPSE: f32 = 1.0;
const SHAPE_RECT: f32 = 2.0;

/// Whether `(lx, ly)`, in the coordinates of an element `w` × `h`, is
/// inside its `path`: the shape the shaders clip to, for the hit test.
pub(crate) fn shape_contains(path: &blinc_core::ClipPath, w: f32, h: f32, lx: f32, ly: f32) -> bool {
    let mut points = Vec::new();
    let s = shape_clip(path, (0.0, 0.0), w, h, IDENTITY, &mut points);
    let [a, b, c, d] = s.params;
    match s.rest[2] {
        k if k == SHAPE_ELLIPSE => {
            let (u, v) = ((lx - a) / c.max(1e-4), (ly - b) / d.max(1e-4));
            u * u + v * v <= 1.0
        }
        k if k == SHAPE_RECT => {
            let r = s.rest[3].min(c * 0.5).min(d * 0.5).max(0.0);
            let (qx, qy) = ((lx - (a + c * 0.5)).abs() - c * 0.5 + r, (ly - (b + d * 0.5)).abs() - d * 0.5 + r);
            let outside = (qx.max(0.0).powi(2) + qy.max(0.0).powi(2)).sqrt() + qx.max(qy).min(0.0) - r;
            outside <= 0.0
        }
        k if k == SHAPE_POLYGON => {
            let (first, count) = (a as usize * 2, b as usize);
            let at = |i: usize| (points[first + 2 * i], points[first + 2 * i + 1]);
            // The nonzero rule, as CSS's default and the shaders'.
            let mut winding = 0;
            for i in 1..count {
                let ((x0, y0), (x1, y1)) = (at(i - 1), at(i));
                // A point at 1e30 parts two rings of a path.
                if x0 >= 1e29 || x1 >= 1e29 {
                    continue;
                }
                let side = (x1 - x0) * (ly - y0) - (lx - x0) * (y1 - y0);
                if y0 <= ly {
                    if y1 > ly && side > 0.0 {
                        winding += 1;
                    }
                } else if y1 <= ly && side < 0.0 {
                    winding -= 1;
                }
            }
            winding != 0
        }
        _ => true,
    }
}

/// Adds `ring` to `points` from a row's start, closed back to its first
/// point when `close`, and gives the shape: its first row and point count.
fn polygon(points: &mut Vec<f32>, ring: &[(f32, f32)], close: bool) -> (f32, [f32; 4], f32) {
    if ring.len() < 3 {
        return (0.0, [0.0; 4], 0.0);
    }
    while points.len() % 4 != 0 {
        points.push(0.0);
    }
    let first = points.len() / 4;
    for &(px, py) in ring {
        points.push(px);
        points.push(py);
    }
    let mut count = ring.len();
    if close {
        points.push(ring[0].0);
        points.push(ring[0].1);
        count += 1;
    }
    (SHAPE_POLYGON, [first as f32, count as f32, 0.0, 0.0], 0.0)
}

/// `path` on a box `w` × `h` at `(x, y)` in layout coordinates, drawn under
/// `m`: CSS's resolution of each shape, a circle's radius against the box's
/// diagonal over √2 and an unset one reaching the closest side.
fn shape_clip(path: &blinc_core::ClipPath, (x, y): (f32, f32), w: f32, h: f32, m: Affine, points: &mut Vec<f32>) -> ShapeClip {
    use blinc_core::ClipPath as C;
    let diagonal = (w * w + h * h).sqrt() / std::f32::consts::SQRT_2;
    let (kind, params, radius) = match path {
        C::Circle { radius, center } => {
            let (cx, cy) = (center.0.resolve(w), center.1.resolve(h));
            let r = radius.map_or((cx).min(w - cx).min(cy).min(h - cy), |r| r.resolve(diagonal));
            (SHAPE_ELLIPSE, [cx, cy, r, r], 0.0)
        }
        C::Ellipse { rx, ry, center } => {
            let (cx, cy) = (center.0.resolve(w), center.1.resolve(h));
            let rx = rx.map_or(cx.min(w - cx), |r| r.resolve(w));
            let ry = ry.map_or(cy.min(h - cy), |r| r.resolve(h));
            (SHAPE_ELLIPSE, [cx, cy, rx, ry], 0.0)
        }
        C::Inset { top, right, bottom, left, round } => {
            let (t, r, b, l) = (top.resolve(h), right.resolve(w), bottom.resolve(h), left.resolve(w));
            (SHAPE_RECT, [l, t, (w - l - r).max(0.0), (h - t - b).max(0.0)], round.unwrap_or(0.0))
        }
        C::Rect { top, right, bottom, left, round } => {
            let (t, r, b, l) = (top.resolve(h), right.resolve(w), bottom.resolve(h), left.resolve(w));
            (SHAPE_RECT, [l, t, (r - l).max(0.0), (b - t).max(0.0)], round.unwrap_or(0.0))
        }
        C::Xywh { x: cx, y: cy, w: cw, h: ch, round } => (
            SHAPE_RECT,
            [cx.resolve(w), cy.resolve(h), cw.resolve(w), ch.resolve(h)],
            round.unwrap_or(0.0),
        ),
        C::Polygon { points: corners } => {
            let ring: Vec<(f32, f32)> = corners.iter().map(|(px, py)| (px.resolve(w), py.resolve(h))).collect();
            polygon(points, &ring, true)
        }
        C::Path { vertices } => polygon(points, vertices, false),
    };
    let [a, b, c, d, e, f] = m;
    let det = a * d - b * c;
    let (ia, ib, ic, id) = if det.abs() > 1e-12 {
        (d / det, -b / det, -c / det, a / det)
    } else {
        (1.0, 0.0, 0.0, 1.0)
    };
    let ie = -(ia * e + ic * f);
    let jf = -(ib * e + id * f);
    ShapeClip {
        inverse: [ia, ib, ic, id],
        rest: [ie - x, jf - y, kind, radius],
        params,
    }
}

/// The clips of one record: on screen, and in its own coordinates, and the
/// corner `n` of the innermost rounded one.
#[derive(Clone)]
struct Clipping {
    screen: ([f32; 4], [f32; 4], f32),
    local: Option<([f32; 4], [f32; 4])>,
    n: f32,
    /// The innermost fading clip's rect on screen and its fade distances.
    fade: ([f32; 4], [f32; 4]),
    /// The innermost `clip-path`, if any.
    shape: Option<ShapeClip>,
}

/// The clips under `clips` for a record placed at `origin` in layout
/// coordinates under `m`. Those pushed under `m` itself become its local
/// clip, unless `local` is false; the rest are clipped on screen.
fn clipping(clips: &[Clip], m: Affine, origin: (f32, f32), local: bool) -> Clipping {
    let shares = |c: &Clip| local && m != IDENTITY && c.frame == m;
    // A clip-path clips by its shape alone, not as a rect.
    let rects = clips.iter().filter(|c| c.shape.is_none());
    let on_screen: Vec<Clip> = rects.clone().filter(|c| !shares(c)).copied().collect();
    let in_frame: Vec<Clip> = rects
        .filter(|c| shares(c))
        .map(|c| Clip {
            rect: c.layout,
            radii: c.layout_radii,
            ..*c
        })
        .collect();
    let local = if in_frame.is_empty() {
        None
    } else {
        let (r, radii, _) = clip_data(&in_frame);
        Some(([r[0] - origin.0, r[1] - origin.1, r[2], r[3]], radii))
    };
    // One corner shape per record: the innermost rounded clip's, which a
    // single squircle parent clipping its children makes exact.
    let n = clips
        .iter()
        .rev()
        .find(|c| c.layout_radii.iter().any(|&r| r > 0.0))
        .map_or(1.0, |c| c.n);
    let fade = clips
        .iter()
        .rev()
        .find(|c| c.fade.iter().any(|&f| f > 0.0))
        .map_or(([0.0; 4], [0.0; 4]), |c| (c.rect, c.fade));
    Clipping {
        screen: clip_data(&on_screen),
        local,
        n,
        fade,
        shape: clips.iter().rev().find_map(|c| c.shape),
    }
}

/// The clip every primitive under `clips` gets: the intersection of the
/// rects, with a corner rounded only where the intersection still reaches
/// into the rounded corner of the clip it came from. Blinc's
/// `GpuPaintContext::get_clip_data` for rect and rounded-rect clips.
fn clip_data(clips: &[Clip]) -> ([f32; 4], [f32; 4], f32) {
    if clips.is_empty() {
        return (NO_CLIP, [0.0; 4], CLIP_NONE);
    }
    let (mut min_x, mut min_y) = (f32::NEG_INFINITY, f32::NEG_INFINITY);
    let (mut max_x, mut max_y) = (f32::INFINITY, f32::INFINITY);
    // Per corner: the largest radius and the bounds of the clip it came from.
    let mut sources = [(0.0f32, [0.0f32; 4]); 4];
    for clip in clips {
        let [x, y, w, h] = clip.rect;
        min_x = min_x.max(x);
        min_y = min_y.max(y);
        max_x = max_x.min(x + w);
        max_y = max_y.min(y + h);
        for corner in 0..4 {
            if clip.radii[corner] > sources[corner].0 {
                sources[corner] = (clip.radii[corner], [x, y, x + w, y + h]);
            }
        }
    }
    let mut radii = [0.0f32; 4];
    // How far the intersection's edges sit inside the source's, per corner.
    let insets = |c: usize, s: [f32; 4]| match c {
        0 => (min_x - s[0], min_y - s[1]),
        1 => (s[2] - max_x, min_y - s[1]),
        2 => (s[2] - max_x, s[3] - max_y),
        _ => (min_x - s[0], s[3] - max_y),
    };
    for (corner, &(r, source)) in sources.iter().enumerate() {
        if r > 0.0 {
            let (dx, dy) = insets(corner, source);
            if dx < r && dy < r {
                radii[corner] = (r - dx.max(0.0)).clamp(0.0, r);
            }
        }
    }
    (
        [
            min_x,
            min_y,
            (max_x - min_x).max(0.0),
            (max_y - min_y).max(0.0),
        ],
        radii,
        CLIP_RECT,
    )
}

fn rgba(c: Color, opacity: f32) -> [f32; 4] {
    [c.r, c.g, c.b, c.a * opacity]
}

/// Sets `p`'s fill colours, gradient geometry in pixels and fill type to
/// `brush` over its bounds; Blinc's `brush_to_colors` then
/// `obb_to_rect_coords`, with up to three stops: the first, the last and
/// the one between them. False for brushes drawn elsewhere.
fn fill(p: &mut Primitive, brush: &Brush, opacity: f32) -> bool {
    let [x, y, w, h] = p.bounds;
    match brush {
        Brush::Solid(c) => {
            p.color = rgba(*c, opacity);
            p.color2 = p.color;
            true
        }
        Brush::Gradient(g) => {
            let (stops, space, fill_type, params) = match g {
                Gradient::Linear {
                    start,
                    end,
                    stops,
                    space,
                    ..
                } => (stops, space, FILL_LINEAR, [start.x, start.y, end.x, end.y]),
                Gradient::Radial {
                    center,
                    radius,
                    stops,
                    space,
                    ..
                } => (
                    stops,
                    space,
                    FILL_RADIAL,
                    [center.x, center.y, *radius, 0.0],
                ),
                Gradient::Conic {
                    center,
                    stops,
                    space,
                    ..
                } => (stops, space, FILL_RADIAL, [center.x, center.y, 100.0, 0.0]),
            };
            let (c1, c2) = match (stops.first(), stops.last()) {
                (Some(a), Some(b)) => (rgba(a.color, opacity), rgba(b.color, opacity)),
                _ => ([1.0, 1.0, 1.0, opacity], [1.0, 1.0, 1.0, opacity]),
            };
            let first = stops.first().map_or(0.0, |s| s.offset);
            let last = if stops.len() > 1 {
                stops[stops.len() - 1].offset
            } else {
                1.0
            };
            if stops.len() >= 3 {
                let middle = &stops[stops.len() / 2];
                p.via = rgba(middle.color, opacity);
                p.offsets = [first, middle.offset, last, 1.0];
            } else {
                p.offsets = [first, 0.0, last, 0.0];
            }
            // User-space points are in the node's own coordinates.
            let params = match (space, fill_type == FILL_RADIAL) {
                (GradientSpace::ObjectBoundingBox, true) => [
                    x + params[0] * w,
                    y + params[1] * h,
                    params[2] * w.max(h),
                    params[3],
                ],
                (GradientSpace::ObjectBoundingBox, false) => [
                    x + params[0] * w,
                    y + params[1] * h,
                    x + params[2] * w,
                    y + params[3] * h,
                ],
                (GradientSpace::UserSpace, true) => {
                    [x + params[0], y + params[1], params[2], params[3]]
                }
                (GradientSpace::UserSpace, false) => {
                    [x + params[0], y + params[1], x + params[2], y + params[3]]
                }
            };
            p.color = c1;
            p.color2 = c2;
            p.gradient = params;
            p.fill_type = fill_type;
            true
        }
        Brush::Glass(_) | Brush::Blur(_) | Brush::Image(_) => false,
    }
}

/// The fields of one record, before packing.
#[derive(Clone)]
struct Primitive {
    bounds: [f32; 4],
    radii: [f32; 4],
    color: [f32; 4],
    color2: [f32; 4],
    border: [f32; 4],
    border_color: [f32; 4],
    shadow: [f32; 4],
    shadow_color: [f32; 4],
    gradient: [f32; 4],
    kind: f32,
    fill_type: f32,
    corner_shape: [f32; 4],
    via: [f32; 4],
    offsets: [f32; 4],
    affine: [f32; 4],
    /// Each side's border colour, top, right, bottom, left.
    side_colors: [[f32; 4]; 4],
}

impl Primitive {
    fn new(kind: f32, bounds: [f32; 4], radii: [f32; 4]) -> Self {
        Self {
            bounds,
            radii,
            color: [0.0; 4],
            color2: [0.0; 4],
            border: [0.0; 4],
            border_color: [0.0; 4],
            shadow: [0.0; 4],
            shadow_color: [0.0; 4],
            gradient: [0.0, 0.0, 1.0, 0.0],
            kind,
            fill_type: FILL_SOLID,
            corner_shape: [1.0; 4],
            via: [0.0; 4],
            offsets: [0.0, 0.0, 1.0, 0.0],
            affine: [1.0, 0.0, 0.0, 1.0],
            side_colors: [[0.0; 4]; 4],
        }
    }

    /// Places the box, laid out at `(x, y)`, on screen through `m`.
    fn place(&mut self, m: Affine, x: f32, y: f32) {
        let (sx, sy) = apply(m, x, y);
        self.bounds[0] = sx;
        self.bounds[1] = sy;
        self.affine = [m[0], m[1], m[2], m[3]];
    }

    /// The node's own corner shape, which the theme may yet smooth unless locked.
    fn shape_from(&mut self, props: &RenderProps, shapes: &Shapes) {
        self.corner_shape = shapes.resolve(
            props.corner_shape.to_array(),
            self.radii,
            self.bounds[2],
            self.bounds[3],
            props.corner_shape_locked,
        );
    }

    fn push(&self, clipping: &Clipping, out: &mut Vec<f32>) {
        let clip = &clipping.screen;
        let (row6, row7) = match &clipping.local {
            Some((rect, radii)) => (rect, radii),
            None => (&self.shadow, &self.shadow_color),
        };
        for row in [
            &self.bounds,
            &self.radii,
            &self.color,
            &self.color2,
            &self.border,
            &self.border_color,
            row6,
            row7,
            &clip.0,
            &clip.1,
            &self.gradient,
        ] {
            out.extend_from_slice(row);
        }
        let clips = clip.2 + if clipping.local.is_some() { 2.0 } else { 0.0 };
        out.extend_from_slice(&[self.kind, self.fill_type, clips, clipping.n]);
        out.extend_from_slice(&self.corner_shape);
        out.extend_from_slice(&self.via);
        out.extend_from_slice(&self.offsets);
        out.extend_from_slice(&self.affine);
        for c in &self.side_colors {
            out.extend_from_slice(c);
        }
        out.extend_from_slice(&clipping.fade.0);
        out.extend_from_slice(&clipping.fade.1);
        match &clipping.shape {
            Some(c) => {
                out.extend_from_slice(&c.inverse);
                out.extend_from_slice(&c.rest);
                out.extend_from_slice(&c.params);
            }
            None => out.extend_from_slice(&[0.0; 12]),
        }
    }
}

/// Appends the records of `node` and everything below it, which sits at
/// `origin` in its parent's layout, under the ancestors' combined
/// `opacity`, their transform `m` and the clips they pushed. `color` is
/// the text colour it inherits: its own wins, and what it ends up with
/// passes to its children. Inheritance is resolved here rather than copied
/// into descendants' props, so a node built or recoloured at any time
/// inherits what its ancestors have now.
#[allow(clippy::too_many_arguments)]
pub fn append(
    tree: &Tree,
    node: LayoutNodeId,
    origin: (f32, f32),
    opacity: f32,
    color: [f32; 4],
    m: Affine,
    clips: &mut Vec<Clip>,
    glyphs: &mut Glyphs,
    out: &mut Vec<f32>,
) {
    let Some(layout) = tree.layout.get_layout(node) else {
        return;
    };
    let x = origin.0 + layout.location.x;
    let y = origin.1 + layout.location.y;
    let (w, h) = (layout.size.width, layout.size.height);
    // Fills and shapes are drawn in the box's own coordinates.
    let local = [0.0, 0.0, w, h];
    let mut m = m;
    let mut opacity = opacity;
    let color = tree
        .props
        .get(&node)
        .and_then(|p| p.text_color)
        .unwrap_or(color);
    let mut pushed = false;
    let mut shaped = false;
    // Where its layer's begin record is in `out`, the layer's opacity, colour filter, blur and drop shadow.
    let mut layer: Option<(usize, f32, ColorMatrix, f32, Option<blinc_core::layer::Shadow>)> = None;
    // A border drawn after the children, with the clips its node is drawn under.
    let mut after: Option<(Primitive, Clipping)> = None;
    if let Some(props) = tree.props.get(&node) {
        if !props.visible {
            return;
        }
        // The node's transform turns it about its centre, after its ancestors'.
        if let Some(Transform::Affine2D(t)) = &props.transform {
            let (cx, cy) = (x + w / 2.0, y + h / 2.0);
            let about = compose(
                [1.0, 0.0, 0.0, 1.0, cx, cy],
                compose(t.elements, [1.0, 0.0, 0.0, 1.0, -cx, -cy]),
            );
            m = compose(m, about);
        }
        // A group with opacity over more than one painted node is drawn into a
        // layer and faded as one; otherwise multiplying the opacity in is exact.
        let filtered = props.filter.as_ref().map(filter_matrix).filter(|m| *m != IDENTITY_MATRIX);
        let blur = props.filter.as_ref().map_or(0.0, |f| f.blur.max(0.0));
        let dropped = props.filter.as_ref().and_then(|f| f.drop_shadow).filter(|s| s.color.a > 0.0);
        if filtered.is_some() || blur > 0.0 || dropped.is_some() || (props.opacity < 1.0 && painted_at_least(tree, node, 2)) {
            layer = Some((out.len(), opacity * props.opacity, filtered.unwrap_or(IDENTITY_MATRIX), blur, dropped));
            Primitive::new(PRIM_LAYER_BEGIN, [0.0; 4], [0.0; 4]).push(&clipping(&[], IDENTITY, (0.0, 0.0), false), out);
            opacity = 1.0;
        } else {
            opacity *= props.opacity;
        }
        // A clip-path clips the node itself, its shadows and everything inside it.
        if let Some(path) = &props.clip_path {
            clips.push(Clip {
                rect: NO_CLIP,
                radii: [0.0; 4],
                layout: NO_CLIP,
                layout_radii: [0.0; 4],
                frame: m,
                n: 1.0,
                fade: [0.0; 4],
                shape: Some(shape_clip(path, (x, y), w, h, m, &mut glyphs.points)),
            });
            shaped = true;
        }
        let r: CornerRadius = props.border_radius;
        let radii = [r.top_left, r.top_right, r.bottom_right, r.bottom_left];
        // A shadow's local-clip rows hold the shadow itself.
        let shadow_clip = clipping(clips, m, (x, y), false);
        let clip = clipping(clips, m, (x, y), true);

        // Outer shadows under the fill; inset ones go over it, after.
        for s in props.shadow.iter().rev().filter(|s| !s.inset) {
            let mut p = Primitive::new(PRIM_SHADOW, local, radii);
            p.shape_from(props, &glyphs.shapes);
            p.shadow = [s.offset_x, s.offset_y, s.blur, s.spread];
            p.shadow_color = rgba(s.color, opacity);
            p.place(m, x, y);
            if p.shadow_color[3] > 0.0 {
                p.push(&shadow_clip, out);
            }
        }

        let sides = border_sides(props);
        let side_colors = border_side_colors(props);
        let border = (0..4).any(|i| sides[i] > 0.0 && side_colors[i].is_some());
        // A border with no background draws over a transparent fill.
        let transparent = Brush::Solid(Color::TRANSPARENT);
        // An image background, a bitmap ashui names by its slot, is drawn over the box under the border.
        let image = match &props.background {
            Some(Brush::Image(i)) => i.source.strip_prefix("ashui:bitmap:").and_then(|s| s.parse::<i32>().ok()).map(|slot| (slot, i.opacity)),
            _ => None,
        };
        if let Some((slot, alpha)) = image {
            let mut ring_clips = clips.to_vec();
            ring_clips.push(own_box(props, [x, y, w, h], m, &glyphs.shapes));
            let mut rec = Primitive::new(PRIM_IMAGE, [0.0, 0.0, w, h], [0.0; 4]);
            rec.color = [1.0, 1.0, 1.0, opacity * alpha];
            rec.color2 = [1.0, 1.0, 1.0, opacity * alpha];
            let on_screen = glyphs.display_scale * (m[0] * m[3] - m[1] * m[2]).abs().sqrt();
            rec.gradient = [slot as f32, on_screen, 0.0, 0.0];
            rec.place(m, x, y);
            rec.push(&clipping(&ring_clips, m, (x, y), true), out);
        }
        // A glass or blur brush draws what is behind the box, blurred and
        // filtered, in place of a fill; the border still draws, over nothing.
        let behind = props.background.as_ref().and_then(backdrop_of);
        if let Some((blur, matrix)) = behind {
            let scale = (m[0] * m[3] - m[1] * m[2]).abs().sqrt();
            let mut b = Primitive::new(PRIM_BACKDROP, local, radii);
            b.shape_from(props, &glyphs.shapes);
            // Deviation in target pixels; how far the row pass reaches past the box, in layout units.
            b.color = [blur * scale * glyphs.display_scale, 3.0 * blur * scale, 0.0, 0.0];
            b.color2 = matrix[0];
            b.border = matrix[1];
            b.border_color = matrix[2];
            b.place(m, x, y);
            b.push(&clip, out);
        }
        let background = if image.is_some() || behind.is_some() { None } else { props.background.as_ref() };
        let brush = background.or(border.then_some(&transparent));
        let mut p = Primitive::new(PRIM_RECT, local, radii);
        p.shape_from(props, &glyphs.shapes);
        if brush.is_some_and(|b| fill(&mut p, b, opacity)) {
            if border {
                p.border = sides;
                p.side_colors = side_colors.map(|c| c.map_or([0.0; 4], |c| rgba(c, opacity)));
                // The most opaque side's, which says whether there is a border to draw.
                p.border_color = p.side_colors.iter().copied().fold([0.0; 4], |a, c| if c[3] > a[3] { c } else { a });
            }
            p.place(m, x, y);
            // A node that clips its children draws its border after them, so
            // where its clip's curve and its border's inner edge differ by a
            // fraction of a pixel, a child cannot paint over the border.
            let mut ring_after = None;
            if clips_children(tree, node) && p.border_color[3] > 0.0 {
                let mut ring = p.clone();
                ring.color = [0.0; 4];
                ring.color2 = [0.0; 4];
                ring.fill_type = FILL_SOLID;
                p.border = [0.0; 4];
                p.border_color = [0.0; 4];
                ring_after = Some(ring);
            }
            if p.color[3] > 0.0 || p.color2[3] > 0.0 || p.border_color[3] > 0.0 {
                p.push(&clip, out);
            }
            if let Some(ring) = ring_after {
                after = Some((ring, clip));
            }
        }

        // Inset shadows, inside the padding box: over the fill, under the border's inner edge.
        let [top, right, bottom, left] = sides;
        let inner = [0.0, 0.0, (w - left - right).max(0.0), (h - top - bottom).max(0.0)];
        let inner_radii = radii.map(|r| (r - top.max(right).max(bottom).max(left)).max(0.0));
        for s in props.shadow.iter().rev().filter(|s| s.inset) {
            let mut p = Primitive::new(PRIM_SHADOW, inner, inner_radii);
            p.shape_from(props, &glyphs.shapes);
            p.fill_type = 1.0;
            p.shadow = [s.offset_x, s.offset_y, s.blur, s.spread];
            p.shadow_color = rgba(s.color, opacity);
            p.place(m, x + left, y + top);
            if p.shadow_color[3] > 0.0 {
                p.push(&shadow_clip, out);
            }
        }

        // An outline: a ring outside the box, `offset` away from it, its
        // corners following the box's, as CSS draws one and Tailwind a ring.
        if let Some(oc) = props.outline_color.filter(|_| props.outline_width > 0.0) {
            let grow = props.outline_offset + props.outline_width;
            let ring_radii = radii.map(|r| if r > 0.0 { r + grow } else { 0.0 });
            let mut o = Primitive::new(PRIM_RECT, [0.0, 0.0, w + 2.0 * grow, h + 2.0 * grow], ring_radii);
            o.shape_from(props, &glyphs.shapes);
            o.fill_type = FILL_SOLID;
            o.border = [props.outline_width; 4];
            o.border_color = rgba(oc, opacity);
            o.side_colors = [o.border_color; 4];
            o.place(m, x - grow, y - grow);
            if o.border_color[3] > 0.0 {
                o.push(&clipping(clips, m, (x - grow, y - grow), true), out);
            }
        }
    }

    if let Some(&slot) = tree.images.get(&node) {
        // An image is clipped to its own rounded corners, as an `<img>` is.
        let rounded = tree.props.get(&node).filter(|p| {
            let r = p.border_radius;
            r.top_left > 0.0 || r.top_right > 0.0 || r.bottom_right > 0.0 || r.bottom_left > 0.0
        });
        match rounded {
            Some(p) => {
                let mut own = clips.clone();
                own.push(own_box(p, [x, y, w, h], m, &glyphs.shapes));
                image_record(tree, node, slot, (x, y), opacity, color, m, &own, glyphs.display_scale, out);
            }
            None => image_record(tree, node, slot, (x, y), opacity, color, m, clips, glyphs.display_scale, out),
        }
    }
    if let Some(context) = tree.layout.text_context(node) {
        text_records(tree, node, context, (x, y, w), opacity, color, m, clips, glyphs, out);
    }

    // Children are clipped to the padding box, rounded by what is left of a
    // uniform radius after a uniform border.
    if clips_children(tree, node) {
        let (sides, r) = tree
            .props
            .get(&node)
            .map(|p| (border_sides(p), p.border_radius))
            .unwrap_or_default();
        let [top, right, bottom, left] = sides;
        let uniform = sides.iter().all(|&s| s == top);
        let inset_radius = if uniform && r.is_uniform() && r.top_left > top {
            r.top_left - top
        } else {
            0.0
        };
        let inner = [
            x + left,
            y + top,
            (w - left - right).max(0.0),
            (h - top - bottom).max(0.0),
        ];
        let (rect, radii) = if m == IDENTITY {
            (inner, [inset_radius; 4])
        } else {
            (bounding(m, inner), [0.0; 4])
        };
        let n = tree.props.get(&node).map_or(1.0, |p| {
            let r = p.border_radius;
            glyphs.shapes.resolve(
                p.corner_shape.to_array(),
                [r.top_left, r.top_right, r.bottom_right, r.bottom_left],
                w,
                h,
                p.corner_shape_locked,
            )[0]
        });
        clips.push(Clip {
            rect,
            radii,
            layout: inner,
            layout_radii: [inset_radius; 4],
            frame: m,
            n,
            fade: tree.props.get(&node).map_or([0.0; 4], |p| {
                let f = p.overflow_fade;
                [f.top, f.right, f.bottom, f.left]
            }),
            shape: None,
        });
        pushed = true;
    }
    // A scroll container's content moves up and left by its offset.
    let scroll = tree.scrolls.get(&node).copied();
    let (sx, sy) = scroll.map_or((0.0, 0.0), |s| (s.x, s.y));
    for child in tree.layout.children(node) {
        append(tree, child, (x - sx, y - sy), opacity, color, m, clips, glyphs, out);
    }
    if let Some(s) = scroll {
        thumbs(tree, node, s, (x, y), opacity, m, clips, out);
    }
    if pushed {
        clips.pop();
    }
    if let Some((ring, clip)) = after {
        ring.push(&clip, out);
    }
    if shaped {
        clips.pop();
    }
    if let Some((begin, alpha, matrix, blur, dropped)) = layer {
        // A blur spreads the layer three of its deviations past what was drawn,
        // and a drop shadow its offset and three of its own.
        let [bx, by, bw, bh] = records_bounds(&out[begin + RECORD_FLOATS..]);
        let spread = (blur * 3.0).ceil();
        let (mut x0, mut y0, mut x1, mut y1) = (bx - spread, by - spread, bx + bw + spread, by + bh + spread);
        if let Some(s) = &dropped {
            // CSS's drop-shadow radius is twice the deviation, as a box shadow's is.
            let reach = (s.blur * 1.5).ceil() + spread;
            x0 = x0.min(bx + s.offset_x - reach);
            y0 = y0.min(by + s.offset_y - reach);
            x1 = x1.max(bx + bw + s.offset_x + reach);
            y1 = y1.max(by + bh + s.offset_y + reach);
        }
        let mut c = Primitive::new(PRIM_LAYER, [x0, y0, x1 - x0, y1 - y0], [0.0; 4]);
        let px = glyphs.display_scale;
        // The blur's standard deviation in the target's pixels, CSS's `blur()` radius.
        c.color = [blur * px, 1.0, 1.0, alpha];
        // The drop shadow, in pixels: its offset and deviation, and its colour, in two rows a layer leaves free.
        if let Some(s) = &dropped {
            c.gradient = [s.offset_x * px, s.offset_y * px, s.blur * 0.5 * px, 0.0];
            c.via = rgba(s.color, 1.0);
        } else {
            c.gradient = [0.0; 4];
        }
        // The colour filter's rows in the rows a box's second colour and border take.
        [c.color2, c.border, c.border_color] = matrix;
        c.push(&clipping(&[], IDENTITY, (0.0, 0.0), false), out);
    }
}

/// A colour filter as an affine map of straight RGB: each row's first three
/// are its weights of r, g and b, its fourth the offset.
/// A glass or blur brush's blur, in layout units, and the colour filter it
/// puts what is behind the box through: Blinc's frosted glass saturates,
/// brightens and adds half its tint; a blur brush mixes its tint over.
fn backdrop_of(brush: &Brush) -> Option<(f32, ColorMatrix)> {
    match brush {
        Brush::Glass(g) => {
            let mut m = saturation(g.saturation);
            m = then(m, [[g.brightness, 0.0, 0.0, 0.0], [0.0, g.brightness, 0.0, 0.0], [0.0, 0.0, g.brightness, 0.0]]);
            let t = g.tint;
            let k = t.a * 0.5;
            for (row, c) in m.iter_mut().zip([t.r, t.g, t.b]) {
                row[3] += c * k;
            }
            Some((g.blur.max(0.0), m))
        }
        Brush::Blur(b) => {
            let mut m = IDENTITY_MATRIX;
            if let Some(t) = b.tint.filter(|t| t.a > 0.0) {
                let keep = 1.0 - t.a;
                m = [[keep, 0.0, 0.0, t.r * t.a], [0.0, keep, 0.0, t.g * t.a], [0.0, 0.0, keep, t.b * t.a]];
            }
            Some((b.radius.max(0.0), m))
        }
        _ => None,
    }
}

/// Mixes each colour toward its luminance by `1 - s`, with the weights Blinc's glass uses.
fn saturation(s: f32) -> ColorMatrix {
    let (lr, lg, lb) = (0.299 * (1.0 - s), 0.587 * (1.0 - s), 0.114 * (1.0 - s));
    [[lr + s, lg, lb, 0.0], [lr, lg + s, lb, 0.0], [lr, lg, lb + s, 0.0]]
}

type ColorMatrix = [[f32; 4]; 3];

const IDENTITY_MATRIX: ColorMatrix = [[1.0, 0.0, 0.0, 0.0], [0.0, 1.0, 0.0, 0.0], [0.0, 0.0, 1.0, 0.0]];

/// `outer` applied after `inner`.
fn then(inner: ColorMatrix, outer: ColorMatrix) -> ColorMatrix {
    let mut m = [[0.0; 4]; 3];
    for i in 0..3 {
        for j in 0..3 {
            m[i][j] = (0..3).map(|k| outer[i][k] * inner[k][j]).sum();
        }
        m[i][3] = (0..3).map(|k| outer[i][k] * inner[k][3]).sum::<f32>() + outer[i][3];
    }
    m
}

/// The colour filters of `f` as one matrix, in the order Tailwind composes
/// its filter classes: brightness, contrast, grayscale, hue-rotate, invert,
/// saturate, sepia; each by the CSS Filter Effects formula.
fn filter_matrix(f: &blinc_layout::element_style::CssFilter) -> ColorMatrix {
    let diag = |v: f32, o: f32| [[v, 0.0, 0.0, o], [0.0, v, 0.0, o], [0.0, 0.0, v, o]];
    let mut m = IDENTITY_MATRIX;
    if f.brightness != 1.0 {
        m = then(m, diag(f.brightness, 0.0));
    }
    if f.contrast != 1.0 {
        m = then(m, diag(f.contrast, 0.5 - 0.5 * f.contrast));
    }
    if f.grayscale != 0.0 {
        let s = 1.0 - f.grayscale.clamp(0.0, 1.0);
        m = then(m, [
            [0.2126 + 0.7874 * s, 0.7152 - 0.7152 * s, 0.0722 - 0.0722 * s, 0.0],
            [0.2126 - 0.2126 * s, 0.7152 + 0.2848 * s, 0.0722 - 0.0722 * s, 0.0],
            [0.2126 - 0.2126 * s, 0.7152 - 0.7152 * s, 0.0722 + 0.9278 * s, 0.0],
        ]);
    }
    if f.hue_rotate != 0.0 {
        let (sin, cos) = f.hue_rotate.to_radians().sin_cos();
        m = then(m, [
            [0.213 + cos * 0.787 - sin * 0.213, 0.715 - cos * 0.715 - sin * 0.715, 0.072 - cos * 0.072 + sin * 0.928, 0.0],
            [0.213 - cos * 0.213 + sin * 0.143, 0.715 + cos * 0.285 + sin * 0.140, 0.072 - cos * 0.072 - sin * 0.283, 0.0],
            [0.213 - cos * 0.213 - sin * 0.787, 0.715 - cos * 0.715 + sin * 0.715, 0.072 + cos * 0.928 + sin * 0.072, 0.0],
        ]);
    }
    if f.invert != 0.0 {
        let a = f.invert.clamp(0.0, 1.0);
        m = then(m, diag(1.0 - 2.0 * a, a));
    }
    if f.saturate != 1.0 {
        let s = f.saturate;
        m = then(m, [
            [0.213 + 0.787 * s, 0.715 - 0.715 * s, 0.072 - 0.072 * s, 0.0],
            [0.213 - 0.213 * s, 0.715 + 0.285 * s, 0.072 - 0.072 * s, 0.0],
            [0.213 - 0.213 * s, 0.715 - 0.715 * s, 0.072 + 0.928 * s, 0.0],
        ]);
    }
    if f.sepia != 0.0 {
        let s = 1.0 - f.sepia.clamp(0.0, 1.0);
        m = then(m, [
            [0.393 + 0.607 * s, 0.769 - 0.769 * s, 0.189 - 0.189 * s, 0.0],
            [0.349 - 0.349 * s, 0.686 + 0.314 * s, 0.168 - 0.168 * s, 0.0],
            [0.272 - 0.272 * s, 0.534 - 0.534 * s, 0.131 + 0.869 * s, 0.0],
        ]);
    }
    m
}

/// Whether `node`'s subtree paints at least `n` nodes: a fill, a border, a
/// shadow, an outline, text or an image.
fn painted_at_least(tree: &Tree, node: LayoutNodeId, n: usize) -> bool {
    fn count(tree: &Tree, node: LayoutNodeId, found: &mut usize, n: usize) {
        if *found >= n {
            return;
        }
        if let Some(p) = tree.props.get(&node) {
            if !p.visible {
                return;
            }
            let paints = p.background.is_some()
                || (p.border_color.is_some() && p.border_width > 0.0)
                || !p.shadow.is_empty()
                || (p.outline_color.is_some() && p.outline_width > 0.0);
            if paints {
                *found += 1;
            }
        }
        if tree.layout.text_context(node).is_some() || tree.images.contains_key(&node) {
            *found += 1;
        }
        for child in tree.layout.children(node) {
            count(tree, child, found, n);
        }
    }
    let mut found = 0;
    count(tree, node, &mut found, n);
    found >= n
}

/// The bounds on screen, x, y, width, height, of the boxes `records` draw:
/// each turned by its transform, and a shadow grown by its offset, blur and
/// spread. Layer records inside count by their own bounds.
fn records_bounds(records: &[f32]) -> [f32; 4] {
    let (mut x0, mut y0, mut x1, mut y1) = (f32::INFINITY, f32::INFINITY, f32::NEG_INFINITY, f32::NEG_INFINITY);
    for r in records.chunks_exact(RECORD_FLOATS) {
        if r[44] == PRIM_LAYER_BEGIN {
            continue;
        }
        let [x, y, w, h] = [r[0], r[1], r[2], r[3]];
        let [a, b, c, d] = [r[60], r[61], r[62], r[63]];
        // A shadow reaches past its box by its offset, three blurs and its spread.
        let grow = if r[44] == PRIM_SHADOW { r[26] * 3.0 + r[27].max(0.0) + r[24].abs().max(r[25].abs()) } else { 0.0 };
        for (u, v) in [(-grow, -grow), (w + grow, -grow), (-grow, h + grow), (w + grow, h + grow)] {
            let (px, py) = (x + a * u + c * v, y + b * u + d * v);
            x0 = x0.min(px);
            y0 = y0.min(py);
            x1 = x1.max(px);
            y1 = y1.max(py);
        }
    }
    if x0 > x1 {
        return [0.0; 4];
    }
    // Whole pixels around it, so its anti-aliased edge is inside.
    let (x0, y0) = (x0.floor() - 1.0, y0.floor() - 1.0);
    [x0, y0, x1.ceil() + 1.0 - x0, y1.ceil() + 1.0 - y0]
}

/// Whether `node` clips its children: its overflow is not visible on some axis.
fn clips_children(tree: &Tree, node: LayoutNodeId) -> bool {
    tree.layout
        .get_style(node)
        .is_some_and(|s| s.overflow.x != Overflow::Visible || s.overflow.y != Overflow::Visible)
}

/// Width of a scroll thumb, and its gap from the container's edge.
const THUMB: f32 = 4.0;
const THUMB_GAP: f32 = 2.0;
/// The shortest a thumb gets, so a long list still has something to see.
const THUMB_MIN: f32 = 24.0;

/// The thumbs of scroll container `node`, laid out at `(x, y)`: one per
/// axis its content overflows, as long as the visible part is of the whole
/// and as far along as the offset is of the distance it can scroll.
#[allow(clippy::too_many_arguments)]
fn thumbs(tree: &Tree, node: LayoutNodeId, s: crate::node::Scroll, (x, y): (f32, f32), opacity: f32, m: Affine, clips: &[Clip], out: &mut Vec<f32>) {
    let alpha = s.thumb[3] * opacity;
    if alpha <= 0.0 {
        return;
    }
    let Some(layout) = tree.layout.get_layout(node) else {
        return;
    };
    let b = layout.border;
    let (left, top) = (b.left, b.top);
    let (view_w, view_h) = (
        layout.size.width - b.left - b.right,
        layout.size.height - b.top - b.bottom,
    );
    let (content_w, content_h) = (layout.content_size.width, layout.content_size.height);
    let color = [s.thumb[0], s.thumb[1], s.thumb[2], alpha];
    let mut bar = |rect: [f32; 4]| {
        let mut p = Primitive::new(PRIM_RECT, [0.0, 0.0, rect[2], rect[3]], [THUMB / 2.0; 4]);
        p.color = color;
        p.color2 = color;
        p.place(m, x + rect[0], y + rect[1]);
        p.push(&clipping(clips, m, (x + rect[0], y + rect[1]), true), out);
    };
    if content_h > view_h + 0.5 && view_h > 0.0 {
        let track = view_h - 2.0 * THUMB_GAP;
        let len = (track * view_h / content_h).max(THUMB_MIN).min(track);
        let along = (s.y / (content_h - view_h)).clamp(0.0, 1.0) * (track - len);
        bar([left + view_w - THUMB_GAP - THUMB, top + THUMB_GAP + along, THUMB, len]);
    }
    if content_w > view_w + 0.5 && view_w > 0.0 {
        let track = view_w - 2.0 * THUMB_GAP;
        let len = (track * view_w / content_w).max(THUMB_MIN).min(track);
        let along = (s.x / (content_w - view_w)).clamp(0.0, 1.0) * (track - len);
        bar([left + THUMB_GAP + along, top + view_h - THUMB_GAP - THUMB, len, THUMB]);
    }
}

/// The glyph records of a text node laid out at `(x, y)` and `w` wide.
#[allow(clippy::too_many_arguments)]
fn text_records(
    tree: &Tree,
    node: LayoutNodeId,
    context: &blinc_layout::tree::TextMeasureContext,
    (x, y, w): (f32, f32, f32),
    opacity: f32,
    color: [f32; 4],
    m: Affine,
    clips: &[Clip],
    glyphs: &mut Glyphs,
    out: &mut Vec<f32>,
) {
    let props = tree.props.get(&node);
    let color = [color[0], color[1], color[2], color[3] * opacity];
    if color[3] <= 0.0 || context.content.is_empty() {
        return;
    }
    let on_screen = glyphs.display_scale * (m[0] * m[3] - m[1] * m[2]).abs().sqrt();
    let k = text::raster_scale(context.font_size, on_screen);
    let prepared = match text::prepare(
        glyphs.renderer,
        context,
        w,
        props.and_then(|p| p.text_align),
        props.and_then(|p| p.letter_spacing).unwrap_or(0.0),
        color,
        k,
    ) {
        Ok(prepared) => prepared,
        Err(TextError::AtlasFull) => {
            glyphs.atlas_full = true;
            return;
        }
        Err(_) => return,
    };
    // Without rotation or skew, glyphs start on whole device pixels, so their
    // texels land on pixels instead of being resampled between them.
    let snap = m[1] == 0.0 && m[2] == 0.0;
    let display = glyphs.display_scale;
    // Glyphs start half the extra leading below the line box's top, as in CSS.
    let lead = text::half_leading(context, context.font_size * k);
    for g in &prepared.glyphs {
        let [gx, gy, gw, gh] = g.bounds;
        let gy = gy + lead;
        let mut p = Primitive::new(PRIM_TEXT, [0.0, 0.0, gw / k, gh / k], [0.0; 4]);
        p.color = g.color;
        p.gradient = g.uv_bounds;
        p.fill_type = if g.is_color { 1.0 } else { 0.0 };
        let at = (x + gx / k, y + gy / k);
        p.place(m, at.0, at.1);
        if snap {
            p.bounds[0] = (p.bounds[0] * display).round() / display;
            p.bounds[1] = (p.bounds[1] * display).round() / display;
        }
        p.push(&clipping(clips, m, at, true), out);
    }
}

/// The record of an image drawn in the content box of a node laid out at
/// `(x, y)`; an SVG's `currentColor` is `tint`, the node's text colour.
#[allow(clippy::too_many_arguments)]
fn image_record(
    tree: &Tree,
    node: LayoutNodeId,
    slot: i32,
    (x, y): (f32, f32),
    opacity: f32,
    tint: [f32; 4],
    m: Affine,
    clips: &[Clip],
    display_scale: f32,
    out: &mut Vec<f32>,
) {
    let Some(layout) = tree.layout.get_layout(node) else {
        return;
    };
    let (p, b) = (layout.padding, layout.border);
    let left = p.left + b.left;
    let top = p.top + b.top;
    let w = layout.size.width - left - p.right - b.right;
    let h = layout.size.height - top - p.bottom - b.bottom;
    if w <= 0.0 || h <= 0.0 || opacity <= 0.0 {
        return;
    }
    let mut rec = Primitive::new(PRIM_IMAGE, [0.0, 0.0, w, h], [0.0; 4]);
    rec.color = [tint[0], tint[1], tint[2], tint[3] * opacity];
    rec.color2 = [1.0, 1.0, 1.0, opacity];
    let on_screen = display_scale * (m[0] * m[3] - m[1] * m[2]).abs().sqrt();
    rec.gradient = [slot as f32, on_screen, 0.0, 0.0];
    rec.place(m, x + left, y + top);
    // As glyphs: on whole device pixels when nothing turns or slants it.
    if m[1] == 0.0 && m[2] == 0.0 {
        rec.bounds[0] = (rec.bounds[0] * display_scale).round() / display_scale;
        rec.bounds[1] = (rec.bounds[1] * display_scale).round() / display_scale;
    }
    rec.push(&clipping(clips, m, (x + left, y + top), true), out);
}

/// A clip to a node's own rounded box, `rect` in layout coordinates under `m`.
fn own_box(props: &RenderProps, rect: [f32; 4], m: Affine, shapes: &Shapes) -> Clip {
    let r = props.border_radius;
    let radii = [r.top_left, r.top_right, r.bottom_right, r.bottom_left];
    Clip {
        rect: if m == IDENTITY { rect } else { bounding(m, rect) },
        radii: if m == IDENTITY { radii } else { [0.0; 4] },
        layout: rect,
        layout_radii: radii,
        frame: m,
        n: shapes.resolve(props.corner_shape.to_array(), radii, rect[2], rect[3], props.corner_shape_locked)[0],
        fade: [0.0; 4],
        shape: None,
    }
}

/// A node's border widths, top, right, bottom, left: each side's own where
/// one is set, else the border's. An unset side width is negative.
fn border_sides(props: &RenderProps) -> [f32; 4] {
    let s = &props.border_sides;
    let bw = props.border_width;
    let of = |side: &Option<blinc_layout::element::BorderSide>| {
        side.as_ref().map_or(bw, |b| if b.width < 0.0 { bw } else { b.width })
    };
    [of(&s.top), of(&s.right), of(&s.bottom), of(&s.left)]
}

/// A node's border colours, top, right, bottom, left: each side's own where
/// one is set, else the border's; none where neither is. An unset side
/// colour has a NaN red.
fn border_side_colors(props: &RenderProps) -> [Option<Color>; 4] {
    let s = &props.border_sides;
    let of = |side: &Option<blinc_layout::element::BorderSide>| match side {
        Some(b) if !b.color.r.is_nan() => Some(b.color),
        _ => props.border_color,
    };
    [of(&s.top), of(&s.right), of(&s.bottom), of(&s.left)]
}
