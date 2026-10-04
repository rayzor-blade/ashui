//! Which nodes are under a point, found the way the paint walk draws them:
//! through each node's transform, inside the clips its ancestors push, last
//! child on top. Pointer events in ashui are dispatched from this.

use crate::display_list::{Affine, IDENTITY, apply, compose};
use crate::node::Tree;
use blinc_core::Transform;
use blinc_layout::tree::LayoutNodeId;
use hl_abi::{define_prim, vbyte};
use std::ffi::c_void;
use taffy::Overflow;

/// `m` undone, or `None` when `m` flattens the plane.
fn invert(m: Affine) -> Option<Affine> {
    let [a, b, c, d, e, f] = m;
    let det = a * d - b * c;
    if det.abs() < 1e-12 {
        return None;
    }
    let (ia, ib, ic, id) = (d / det, -b / det, -c / det, a / det);
    Some([ia, ib, ic, id, -(ia * e + ic * f), -(ib * e + id * f)])
}

/// A clip on the way down: a rect in layout coordinates, and what takes a
/// point on screen into them.
struct Clip {
    rect: [f32; 4],
    to_layout: Affine,
}

/// A hit node and the point in its own coordinates, from its top-left.
pub struct Hit {
    pub node: LayoutNodeId,
    pub x: f32,
    pub y: f32,
}

/// Appends to `out` the topmost node of `node`'s subtree under `(px, py)` on
/// screen, then each of its ancestors up to `node`; nothing when no node is.
#[allow(clippy::too_many_arguments)]
fn hit(
    tree: &Tree,
    node: LayoutNodeId,
    origin: (f32, f32),
    m: Affine,
    clips: &mut Vec<Clip>,
    px: f32,
    py: f32,
    out: &mut Vec<Hit>,
) -> bool {
    if tree.pass_through.contains(&node) {
        return false;
    }
    let Some(layout) = tree.layout.get_layout(node) else {
        return false;
    };
    let x = origin.0 + layout.location.x;
    let y = origin.1 + layout.location.y;
    let (w, h) = (layout.size.width, layout.size.height);
    let mut m = m;
    if let Some(props) = tree.props.get(&node) {
        if !props.visible {
            return false;
        }
        if let Some(Transform::Affine2D(t)) = &props.transform {
            let (cx, cy) = (x + w / 2.0, y + h / 2.0);
            let about = compose(
                [1.0, 0.0, 0.0, 1.0, cx, cy],
                compose(t.elements, [1.0, 0.0, 0.0, 1.0, -cx, -cy]),
            );
            m = compose(m, about);
        }
    }
    let Some(to_layout) = invert(m) else {
        return false;
    };
    let (lx, ly) = apply(to_layout, px, py);
    let (lx, ly) = (lx - x, ly - y);
    // Outside its clip-path, nothing of the node or inside it is there to hit.
    if let Some(path) = tree.props.get(&node).and_then(|p| p.clip_path.as_ref()) {
        if !crate::display_list::shape_contains(path, w, h, lx, ly) {
            return false;
        }
    }

    let overflow = tree.layout.get_style(node).map(|s| s.overflow);
    let clipped = overflow.is_some_and(|o| o.x != Overflow::Visible || o.y != Overflow::Visible);
    if clipped {
        let bw = tree.props.get(&node).map_or(0.0, |p| p.border_width);
        clips.push(Clip {
            rect: [x + bw, y + bw, (w - 2.0 * bw).max(0.0), (h - 2.0 * bw).max(0.0)],
            to_layout,
        });
    }
    let children = tree.layout.children(node);
    let (sx, sy) = tree.scrolls.get(&node).map_or((0.0, 0.0), |s| (s.x, s.y));
    let mut found = false;
    for &child in children.iter().rev() {
        if hit(tree, child, (x - sx, y - sy), m, clips, px, py, out) {
            found = true;
            break;
        }
    }
    if clipped {
        clips.pop();
    }
    if !found {
        let inside_clips = clips.iter().all(|c| {
            let (cx, cy) = apply(c.to_layout, px, py);
            let [rx, ry, rw, rh] = c.rect;
            cx >= rx && cy >= ry && cx < rx + rw && cy < ry + rh
        });
        found = inside_clips && lx >= 0.0 && ly >= 0.0 && lx < w && ly < h;
    }
    if found {
        out.push(Hit { node, x: lx, y: ly });
    }
    found
}

/// Writes the nodes under `(x, y)` into `out`, the topmost first and then
/// each ancestor up to `root`, as records of a u64 id and the point in that
/// node's coordinates as two f32s, at most `capacity` of them. Returns how
/// many there are.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn hl_blinc_tree_hit_test(
    h: *mut c_void,
    root: u64,
    x: f32,
    y: f32,
    out: *mut vbyte,
    capacity: i32,
) -> i32 {
    let Some(tree) = (unsafe { crate::node::tree(h) }) else {
        return 0;
    };
    let mut hits = Vec::new();
    hit(
        tree,
        LayoutNodeId::from_raw(root),
        (0.0, 0.0),
        IDENTITY,
        &mut Vec::new(),
        x,
        y,
        &mut hits,
    );
    if !out.is_null() {
        let out = out as *mut u8;
        for (i, hit) in hits.iter().take(capacity.max(0) as usize).enumerate() {
            unsafe {
                let at = out.add(i * 16);
                (at as *mut u64).write_unaligned(hit.node.to_raw());
                (at.add(8) as *mut f32).write_unaligned(hit.x);
                (at.add(12) as *mut f32).write_unaligned(hit.y);
            }
        }
    }
    hits.len() as i32
}
define_prim!(
    hlp_blinc_tree_hit_test,
    hl_blinc_tree_hit_test,
    "PXblinc_tree_lffBi_i"
);

fn order(tree: &Tree, node: LayoutNodeId, out: &mut Vec<u64>) {
    if tree.props.get(&node).is_some_and(|p| !p.visible) {
        return;
    }
    out.push(node.to_raw());
    for child in tree.layout.children(node) {
        order(tree, child, out);
    }
}

/// Writes the visible nodes under `root`, `root` first, in document order (a
/// node, then its children's subtrees in turn) into `out` as u64 ids, at
/// most `capacity`. Returns how many there are.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn hl_blinc_tree_order(
    h: *mut c_void,
    root: u64,
    out: *mut vbyte,
    capacity: i32,
) -> i32 {
    let Some(tree) = (unsafe { crate::node::tree(h) }) else {
        return 0;
    };
    let mut ids = Vec::new();
    order(tree, LayoutNodeId::from_raw(root), &mut ids);
    if !out.is_null() {
        let n = ids.len().min(capacity.max(0) as usize);
        unsafe { std::ptr::copy_nonoverlapping(ids.as_ptr(), out as *mut u64, n) };
    }
    ids.len() as i32
}
define_prim!(hlp_blinc_tree_order, hl_blinc_tree_order, "PXblinc_tree_lBi_i");

fn path(tree: &Tree, from: LayoutNodeId, to: LayoutNodeId, out: &mut Vec<u64>) -> bool {
    if from == to {
        out.push(from.to_raw());
        return true;
    }
    for child in tree.layout.children(from) {
        if path(tree, child, to, out) {
            out.push(from.to_raw());
            return true;
        }
    }
    false
}

/// Writes `node` and its ancestors up to `root`, `node` first, into `out` as
/// u64 ids, at most `capacity`. Returns how many there are: 0 when `node`
/// is not under `root`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn hl_blinc_tree_path(
    h: *mut c_void,
    root: u64,
    node: u64,
    out: *mut vbyte,
    capacity: i32,
) -> i32 {
    let Some(tree) = (unsafe { crate::node::tree(h) }) else {
        return 0;
    };
    let mut ids = Vec::new();
    path(tree, LayoutNodeId::from_raw(root), LayoutNodeId::from_raw(node), &mut ids);
    if !out.is_null() {
        let n = ids.len().min(capacity.max(0) as usize);
        unsafe { std::ptr::copy_nonoverlapping(ids.as_ptr(), out as *mut u64, n) };
    }
    ids.len() as i32
}
define_prim!(hlp_blinc_tree_path, hl_blinc_tree_path, "PXblinc_tree_llBi_i");
