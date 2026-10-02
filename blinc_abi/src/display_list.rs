//! The laid-out tree as a flat list of primitives to draw, packed for a GPU
//! vertex buffer: one record of [`RECORD_FLOATS`] f32s per primitive, in
//! paint order.
//!
//! A record is the subset of Blinc's `GpuPrimitive` (blinc_gpu/primitives.rs)
//! that a box needs, field for field, so ashui's shaders are ports of
//! Blinc's `sdf_core` and `sdf_shadow`. Each row is a vec4:
//!
//! | 0  | bounds x, y, width, height (absolute, layout pixels)          |
//! | 1  | corner radii: top-left, top-right, bottom-right, bottom-left   |
//! | 2  | fill colour, or gradient start; straight alpha, opacity applied |
//! | 3  | gradient end colour                                            |
//! | 4  | border widths: top, right, bottom, left                        |
//! | 5  | border colour, opacity applied                                 |
//! | 6  | shadow offset x, offset y, blur, spread                        |
//! | 7  | shadow colour, opacity applied                                 |
//! | 8  | clip bounds x, y, width, height                                |
//! | 9  | clip corner radii                                              |
//! | 10 | gradient: linear x1, y1, x2, y2 or radial cx, cy, r, 0 (pixels) |
//! | 11 | primitive type, fill type, clip type, corner shape locked (1/0) |
//! | 12 | corner shape `n`: top-left, top-right, bottom-right, bottom-left |
//!
//! The walk follows Blinc's `paint/basic.rs`: a node's shadows, last first,
//! then its fill merged with its border, then its children under the clip it
//! pushes when its overflow is not visible. Glass, blur and image brushes
//! draw nothing yet; transforms are not applied. The corner shape is the
//! node's own; ashui applies its theme's squircle to it after the walk.

use crate::node::Tree;
use blinc_core::{Brush, Color, CornerRadius, Gradient, GradientSpace};
use blinc_layout::element::RenderProps;
use blinc_layout::tree::LayoutNodeId;
use taffy::Overflow;

pub const RECORD_FLOATS: usize = 52;

/// `type_info.x`, as Blinc's `PrimitiveType`.
pub const PRIM_RECT: f32 = 0.0;
pub const PRIM_SHADOW: f32 = 3.0;

/// `type_info.y`, as Blinc's `FillType`.
const FILL_SOLID: f32 = 0.0;
const FILL_LINEAR: f32 = 1.0;
const FILL_RADIAL: f32 = 2.0;

/// `type_info.z`, as Blinc's `ClipType`.
const CLIP_NONE: f32 = 0.0;
const CLIP_RECT: f32 = 1.0;

/// Blinc's bounds for "no clip".
const NO_CLIP: [f32; 4] = [-10000.0, -10000.0, 100000.0, 100000.0];

/// A clip a node pushes for its children: a rect, rounded when `radii` are.
#[derive(Clone, Copy)]
pub struct Clip {
    rect: [f32; 4],
    radii: [f32; 4],
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
/// `obb_to_rect_coords`, keeping only the first and last stops as Blinc
/// does. False for brushes drawn elsewhere.
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
    shape_locked: f32,
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
            shape_locked: 0.0,
        }
    }

    /// The node's own corner shape, which the theme may yet smooth unless locked.
    fn shape_from(&mut self, props: &RenderProps) {
        self.corner_shape = props.corner_shape.to_array();
        self.shape_locked = if props.corner_shape_locked { 1.0 } else { 0.0 };
    }

    fn push(&self, clip: &([f32; 4], [f32; 4], f32), out: &mut Vec<f32>) {
        for row in [
            &self.bounds,
            &self.radii,
            &self.color,
            &self.color2,
            &self.border,
            &self.border_color,
            &self.shadow,
            &self.shadow_color,
            &clip.0,
            &clip.1,
            &self.gradient,
        ] {
            out.extend_from_slice(row);
        }
        out.extend_from_slice(&[self.kind, self.fill_type, clip.2, self.shape_locked]);
        out.extend_from_slice(&self.corner_shape);
    }
}

/// Appends the records of `node` and everything below it, which sits at
/// `origin` in its parent, under the ancestors' combined `opacity` and the
/// clips they pushed.
pub fn append(
    tree: &Tree,
    node: LayoutNodeId,
    origin: (f32, f32),
    opacity: f32,
    clips: &mut Vec<Clip>,
    out: &mut Vec<f32>,
) {
    let Some(layout) = tree.layout.get_layout(node) else {
        return;
    };
    let x = origin.0 + layout.location.x;
    let y = origin.1 + layout.location.y;
    let (w, h) = (layout.size.width, layout.size.height);
    let rect = [x, y, w, h];
    let mut opacity = opacity;
    let mut pushed = false;
    if let Some(props) = tree.props.get(&node) {
        if !props.visible {
            return;
        }
        opacity *= props.opacity;
        let r: CornerRadius = props.border_radius;
        let radii = [r.top_left, r.top_right, r.bottom_right, r.bottom_left];
        let clip = clip_data(clips);

        for s in props.shadow.iter().rev() {
            let mut p = Primitive::new(PRIM_SHADOW, rect, radii);
            p.shape_from(props);
            p.shadow = [s.offset_x, s.offset_y, s.blur, s.spread];
            p.shadow_color = rgba(s.color, opacity);
            if p.shadow_color[3] > 0.0 {
                p.push(&clip, out);
            }
        }

        let bw = props.border_width;
        let border = props.border_color.filter(|_| bw > 0.0);
        // A border with no background draws over a transparent fill.
        let transparent = Brush::Solid(Color::TRANSPARENT);
        let brush = props.background.as_ref().or(border.map(|_| &transparent));
        let mut p = Primitive::new(PRIM_RECT, rect, radii);
        p.shape_from(props);
        if brush.is_some_and(|b| fill(&mut p, b, opacity)) {
            if let Some(bc) = border {
                p.border = [bw; 4];
                p.border_color = rgba(bc, opacity);
            }
            if p.color[3] > 0.0 || p.color2[3] > 0.0 || p.border_color[3] > 0.0 {
                p.push(&clip, out);
            }
        }
    }

    // Children are clipped to the padding box, rounded by what is left of a
    // uniform radius after the border.
    let overflow = tree.layout.get_style(node).map(|s| s.overflow);
    if overflow.is_some_and(|o| o.x != Overflow::Visible || o.y != Overflow::Visible) {
        let (bw, r) = tree
            .props
            .get(&node)
            .map(|p| (p.border_width, p.border_radius))
            .unwrap_or_default();
        let inset_radius = if r.is_uniform() && r.top_left > bw {
            r.top_left - bw
        } else {
            0.0
        };
        clips.push(Clip {
            rect: [
                x + bw,
                y + bw,
                (w - 2.0 * bw).max(0.0),
                (h - 2.0 * bw).max(0.0),
            ],
            radii: [inset_radius; 4],
        });
        pushed = true;
    }
    for child in tree.layout.children(node) {
        append(tree, child, (x, y), opacity, clips, out);
    }
    if pushed {
        clips.pop();
    }
}
