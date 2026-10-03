//! The laid-out tree as a flat list of primitives to draw, packed for a GPU
//! vertex buffer: one record of [`RECORD_FLOATS`] f32s per primitive, in
//! paint order.
//!
//! A record is the subset of Blinc's `GpuPrimitive` (blinc_gpu/primitives.rs)
//! that a box needs, field for field, so ashui's shaders are ports of
//! Blinc's `sdf_core` and `sdf_shadow`. Each row is a vec4:
//!
//! | 0  | the box's top-left on screen after transforms, width, height   |
//! | 1  | corner radii: top-left, top-right, bottom-right, bottom-left   |
//! | 2  | fill colour, or gradient start; straight alpha, opacity applied |
//! | 3  | gradient end colour                                            |
//! | 4  | border widths: top, right, bottom, left                        |
//! | 5  | border colour, opacity applied                                 |
//! | 6  | shadow offset x, offset y, blur, spread; or a local clip rect   |
//! | 7  | shadow colour, opacity applied; or the local clip's radii       |
//! | 8  | clip bounds x, y, width, height                                |
//! | 9  | clip corner radii                                              |
//! | 10 | gradient: linear x1, y1, x2, y2 or radial cx, cy, r, 0, in pixels from the box's top-left |
//! | 11 | primitive type, fill type, clips, corner shape locked (1/0)     |
//! | 12 | corner shape `n`: top-left, top-right, bottom-right, bottom-left |
//! | 13 | gradient middle stop colour, opacity applied                   |
//! | 14 | gradient stop offsets: first, middle, last; 1 if there is a middle |
//! | 15 | a, b, c, d: a point `(x, y)` from the box's top-left is at       |
//! |    | `(a·x + c·y, b·x + d·y)` from its screen top-left                |
//!
//! A text node adds one record per glyph, a `PRIM_TEXT` quad whose bounds
//! are the glyph's, whose colour is the text's, whose gradient row is the
//! glyph's rect in its atlas in pixels, and whose fill type is 1 when that
//! is the colour-glyph atlas (see `text`).
//!
//! A node with an image adds a `PRIM_IMAGE` record over its content box,
//! coloured with its text colour, which an SVG's `currentColor` takes, and
//! with its opacity in `color2.a`. Its gradient row holds the image's slot
//! and the device pixels per unit it covers on screen; the caller replaces
//! them with the image's rect in its atlas.
//!
//! The walk follows Blinc's `paint/basic.rs`: a node's shadows, last first,
//! then its fill merged with its border, then its children under the clip it
//! pushes when its overflow is not visible. Glass, blur and image brushes
//! draw nothing yet. A node's 2D transform applies about its centre, after
//! its ancestors'.
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

pub const RECORD_FLOATS: usize = 64;

/// `type_info.x`, as Blinc's `PrimitiveType`.
pub const PRIM_RECT: f32 = 0.0;
pub const PRIM_SHADOW: f32 = 3.0;
pub const PRIM_TEXT: f32 = 7.0;
/// ashui's own: Blinc draws images in a pass of their own.
pub const PRIM_IMAGE: f32 = 32.0;

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
fn compose(outer: Affine, inner: Affine) -> Affine {
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

fn apply(m: Affine, x: f32, y: f32) -> (f32, f32) {
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
}

/// The clips of one record: on screen, and in its own coordinates.
struct Clipping {
    screen: ([f32; 4], [f32; 4], f32),
    local: Option<([f32; 4], [f32; 4])>,
}

/// The clips under `clips` for a record placed at `origin` in layout
/// coordinates under `m`. Those pushed under `m` itself become its local
/// clip, unless `local` is false; the rest are clipped on screen.
fn clipping(clips: &[Clip], m: Affine, origin: (f32, f32), local: bool) -> Clipping {
    let shares = |c: &Clip| local && m != IDENTITY && c.frame == m;
    let on_screen: Vec<Clip> = clips.iter().filter(|c| !shares(c)).copied().collect();
    let in_frame: Vec<Clip> = clips
        .iter()
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
    Clipping {
        screen: clip_data(&on_screen),
        local,
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
    via: [f32; 4],
    offsets: [f32; 4],
    affine: [f32; 4],
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
            via: [0.0; 4],
            offsets: [0.0, 0.0, 1.0, 0.0],
            affine: [1.0, 0.0, 0.0, 1.0],
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
    fn shape_from(&mut self, props: &RenderProps) {
        self.corner_shape = props.corner_shape.to_array();
        self.shape_locked = if props.corner_shape_locked { 1.0 } else { 0.0 };
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
        out.extend_from_slice(&[self.kind, self.fill_type, clips, self.shape_locked]);
        out.extend_from_slice(&self.corner_shape);
        out.extend_from_slice(&self.via);
        out.extend_from_slice(&self.offsets);
        out.extend_from_slice(&self.affine);
    }
}

/// Appends the records of `node` and everything below it, which sits at
/// `origin` in its parent's layout, under the ancestors' combined
/// `opacity`, their transform `m` and the clips they pushed.
pub fn append(
    tree: &Tree,
    node: LayoutNodeId,
    origin: (f32, f32),
    opacity: f32,
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
    let mut pushed = false;
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
        opacity *= props.opacity;
        let r: CornerRadius = props.border_radius;
        let radii = [r.top_left, r.top_right, r.bottom_right, r.bottom_left];
        // A shadow's local-clip rows hold the shadow itself.
        let shadow_clip = clipping(clips, m, (x, y), false);
        let clip = clipping(clips, m, (x, y), true);

        for s in props.shadow.iter().rev() {
            let mut p = Primitive::new(PRIM_SHADOW, local, radii);
            p.shape_from(props);
            p.shadow = [s.offset_x, s.offset_y, s.blur, s.spread];
            p.shadow_color = rgba(s.color, opacity);
            p.place(m, x, y);
            if p.shadow_color[3] > 0.0 {
                p.push(&shadow_clip, out);
            }
        }

        let bw = props.border_width;
        let border = props.border_color.filter(|_| bw > 0.0);
        // A border with no background draws over a transparent fill.
        let transparent = Brush::Solid(Color::TRANSPARENT);
        let brush = props.background.as_ref().or(border.map(|_| &transparent));
        let mut p = Primitive::new(PRIM_RECT, local, radii);
        p.shape_from(props);
        if brush.is_some_and(|b| fill(&mut p, b, opacity)) {
            if let Some(bc) = border {
                p.border = [bw; 4];
                p.border_color = rgba(bc, opacity);
            }
            p.place(m, x, y);
            if p.color[3] > 0.0 || p.color2[3] > 0.0 || p.border_color[3] > 0.0 {
                p.push(&clip, out);
            }
        }
    }

    if let Some(&slot) = tree.images.get(&node) {
        image_record(tree, node, slot, (x, y), opacity, m, clips, glyphs.display_scale, out);
    }
    if let Some(context) = tree.layout.text_context(node) {
        text_records(tree, node, context, (x, y, w), opacity, m, clips, glyphs, out);
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
        let inner = [
            x + bw,
            y + bw,
            (w - 2.0 * bw).max(0.0),
            (h - 2.0 * bw).max(0.0),
        ];
        let (rect, radii) = if m == IDENTITY {
            (inner, [inset_radius; 4])
        } else {
            (bounding(m, inner), [0.0; 4])
        };
        clips.push(Clip {
            rect,
            radii,
            layout: inner,
            layout_radii: [inset_radius; 4],
            frame: m,
        });
        pushed = true;
    }
    for child in tree.layout.children(node) {
        append(tree, child, (x, y), opacity, m, clips, glyphs, out);
    }
    if pushed {
        clips.pop();
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
    m: Affine,
    clips: &[Clip],
    glyphs: &mut Glyphs,
    out: &mut Vec<f32>,
) {
    let props = tree.props.get(&node);
    let color = props
        .and_then(|p| p.text_color)
        .unwrap_or([0.0, 0.0, 0.0, 1.0]);
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
    for g in &prepared.glyphs {
        let [gx, gy, gw, gh] = g.bounds;
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

/// The record of an image drawn in the content box of a node laid out at `(x, y)`.
#[allow(clippy::too_many_arguments)]
fn image_record(
    tree: &Tree,
    node: LayoutNodeId,
    slot: i32,
    (x, y): (f32, f32),
    opacity: f32,
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
    let props = tree.props.get(&node);
    let tint = props.and_then(|p| p.text_color).unwrap_or([0.0, 0.0, 0.0, 1.0]);
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
