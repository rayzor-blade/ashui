//! The layout tree as a Haxe handle, and the per-frame steps that drive it:
//! applying queued property writes, computing layout, reading bounds.
//!
//! Every handle is a view onto one Blinc tree for the whole process. Blinc
//! keeps one queue of property writes and one binding registry, both keyed
//! by node id, and node ids are unique only within a Blinc tree; with one
//! tree they are unique everywhere, so a write or binding can never reach
//! another handle's node. A handle owns the nodes it created, and dropping
//! or disposing it removes them.

use crate::hl::{handle_mut, into_handle, opt_string_from, string_from, take_handle};
use crate::layout_router::take_pending_text;
use crate::reactive::collect_released;
use blinc_layout::binding::unregister_node;
use blinc_layout::div::GenericFont;
use blinc_layout::element::RenderProps;
use blinc_layout::stateful::take_pending_partial_prop_updates;
use blinc_layout::tree::{LayoutNodeId, LayoutTree, TextMeasureContext};
use hl_abi::{define_prim, vbyte};
use std::collections::HashMap;
use std::ffi::c_void;
use std::cell::UnsafeCell;
use std::sync::{Mutex, Once};
use taffy::prelude::{AvailableSpace, Size, Style};

pub struct Tree {
    pub(crate) layout: LayoutTree,
    /// Visual properties per node; `LayoutTree` holds only styles.
    pub(crate) props: HashMap<LayoutNodeId, RenderProps>,
    /// Set by removals, so the next flush drops props of nodes now gone.
    pruned: bool,
    /// Every live node and the handle that created it.
    owners: HashMap<LayoutNodeId, u64>,
    /// Nodes that draw an image in their content box: an SVG or a bitmap,
    /// named by a slot the caller resolves after the walk.
    pub(crate) images: HashMap<LayoutNodeId, i32>,
    /// Nodes that paint with the GPU themselves in their content box, named
    /// by a slot the caller resolves while the frame is drawn.
    pub(crate) canvases: HashMap<LayoutNodeId, i32>,
    /// Scroll containers: how far their content is scrolled, and their thumb.
    pub(crate) scrolls: HashMap<LayoutNodeId, Scroll>,
    /// Nodes the hit test passes through, with everything inside them, as CSS's `pointer-events: none`.
    pub(crate) pass_through: std::collections::HashSet<LayoutNodeId>,
    /// Nodes drawn as a notch: signed corner radii, then the top and bottom edges' modifiers.
    pub(crate) notches: HashMap<LayoutNodeId, [[f32; 4]; 3]>,
    /// Nodes drawn away from their layout while a layout animation runs:
    /// moved by (dx, dy), and at size (w, h) when w is not negative.
    pub(crate) visuals: HashMap<LayoutNodeId, [f32; 4]>,
    /// Each text node's CSS line-height, a multiple of its font size. Its
    /// measure context holds that over the face's own line height instead,
    /// which is how Blinc reads it.
    line_heights: HashMap<LayoutNodeId, f32>,
}

/// A scroll container's state, which the paint walk and the hit test read.
#[derive(Clone, Copy, Default)]
pub struct Scroll {
    /// How far the content is moved up and left, in layout units.
    pub x: f32,
    pub y: f32,
    /// The thumb's colour, straight alpha; transparent hides it.
    pub thumb: [f32; 4],
}

/// What a Haxe `blinc_tree` handle holds: which of the shared tree's nodes
/// are its own.
struct TreeHandle {
    id: u64,
    /// Its nodes are already gone: disposed, so its drop queues nothing.
    released: bool,
}

/// The one tree. The runtime calls in from one thread, and no call into it
/// re-enters another, so a plain cell suffices.
struct Shared(UnsafeCell<Option<Tree>>);
unsafe impl Sync for Shared {}
static SHARED: Shared = Shared(UnsafeCell::new(None));
static NEXT_HANDLE: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(1);

fn shared() -> &'static mut Tree {
    unsafe {
        (*SHARED.0.get()).get_or_insert_with(|| Tree {
            layout: LayoutTree::new(),
            props: HashMap::new(),
            pruned: false,
            owners: HashMap::new(),
            images: HashMap::new(),
            canvases: HashMap::new(),
            scrolls: HashMap::new(),
            pass_through: std::collections::HashSet::new(),
            notches: HashMap::new(),
            visuals: HashMap::new(),
            line_heights: HashMap::new(),
        })
    }
}

/// Handles dropped since the last flush, whose nodes are still in the tree.
/// A handle may be dropped by its finalizer, inside a collection, where
/// touching the tree or the binding registry is not safe, so the next flush
/// removes them; disposing a handle removes them at once instead.
static RELEASED_HANDLES: Mutex<Vec<u64>> = Mutex::new(Vec::new());

impl Drop for TreeHandle {
    fn drop(&mut self) {
        if self.released {
            return;
        }
        RELEASED_HANDLES
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .push(self.id);
    }
}

/// The shared tree, through a live handle; `None` for a null or disposed one.
///
/// # Safety
/// `h` must be null or a `blinc_tree` handle.
pub(crate) unsafe fn tree<'a>(h: *mut c_void) -> Option<&'a mut Tree> {
    unsafe { handle_mut::<TreeHandle>(h) }.map(|_| shared())
}

/// The id of the handle `h`, for the nodes it creates.
unsafe fn owner(h: *mut c_void) -> u64 {
    unsafe { handle_mut::<TreeHandle>(h) }.map_or(0, |t| t.id)
}

/// Removes every node `handle` created, with its bindings and props.
fn release_handle(tree: &mut Tree, handle: u64) {
    let nodes: Vec<LayoutNodeId> = tree
        .owners
        .iter()
        .filter(|&(_, &o)| o == handle)
        .map(|(&n, _)| n)
        .collect();
    forget(tree, &nodes);
    for node in nodes {
        tree.layout.remove_node(node);
        tree.props.remove(&node);
        tree.images.remove(&node);
        tree.canvases.remove(&node);
        tree.scrolls.remove(&node);
    }
}

fn id(raw: u64) -> LayoutNodeId {
    LayoutNodeId::from_raw(raw)
}

/// `node` and every node below it.
fn subtree(layout: &LayoutTree, node: LayoutNodeId) -> Vec<LayoutNodeId> {
    let mut nodes = vec![node];
    let mut i = 0;
    while i < nodes.len() {
        nodes.extend(layout.children(nodes[i]));
        i += 1;
    }
    nodes
}

/// Drop the property bindings of nodes about to be deleted, so a computed
/// bound only to them can be released, and stop tracking them.
fn forget(tree: &mut Tree, nodes: &[LayoutNodeId]) {
    for node in nodes {
        unregister_node(*node);
        tree.owners.remove(node);
        tree.line_heights.remove(node);
    }
}

/// Delete every node below `parent`, as `LayoutTree::clear_children` does.
fn clear_children(tree: &mut Tree, parent: LayoutNodeId) {
    for child in tree.layout.children(parent) {
        let nodes = subtree(&tree.layout, child);
        forget(tree, &nodes);
    }
    tree.layout.clear_children(parent);
    tree.pruned = true;
}

// ============================================================================
// LIFECYCLE AND NODES
// ============================================================================

/// Blinc measures text with real fonts once its measurer is installed, which
/// must happen before the first tree holds text; without it every width is an
/// estimate. Installed once per process.
static TEXT_MEASURER: Once = Once::new();

#[unsafe(no_mangle)]
pub extern "C" fn hl_blinc_tree_new() -> *mut c_void {
    // The renderer's own registry, so layout measures with the faces text is drawn with.
    TEXT_MEASURER.call_once(|| blinc_layout::init_text_measurer_with_registry(crate::text::renderer().font_registry()));
    shared();
    into_handle(TreeHandle {
        id: NEXT_HANDLE.fetch_add(1, std::sync::atomic::Ordering::Relaxed),
        released: false,
    })
}
define_prim!(hlp_blinc_tree_new, hl_blinc_tree_new, "P_Xblinc_tree_");

#[unsafe(no_mangle)]
pub unsafe extern "C" fn hl_blinc_tree_create_node(h: *mut c_void) -> u64 {
    let Some(tree) = (unsafe { tree(h) }) else {
        return 0;
    };
    let node = tree.layout.create_node(Style::default());
    tree.owners.insert(node, unsafe { owner(h) });
    node.to_raw()
}
define_prim!(
    hlp_blinc_tree_create_node,
    hl_blinc_tree_create_node,
    "PXblinc_tree__l"
);

/// `flags` bit 0 is wrap and bit 1 italic; they share an argument because
/// Ash's interpreter passes at most eight arguments to a native taking floats.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn hl_blinc_tree_create_text_node(
    h: *mut c_void,
    content: *const vbyte,
    font_name: *const vbyte,
    font_size: f32,
    line_height: f32,
    font_weight: i32,
    generic_font: i32,
    flags: i32,
) -> u64 {
    let Some(tree) = (unsafe { tree(h) }) else {
        return 0;
    };
    let mut context = TextMeasureContext {
        content: unsafe { string_from(content) },
        font_size,
        line_height,
        letter_spacing: 0.0,
        wrap: flags & 1 != 0,
        // No family of its own is the system face: the platform's UI face where it is installed.
        font_name: unsafe { opt_string_from(font_name) }.or_else(|| if generic_font == 0 { crate::text::system_ui() } else { None }),
        generic_font: match generic_font {
            1 => GenericFont::Monospace,
            2 => GenericFont::Serif,
            3 => GenericFont::SansSerif,
            _ => GenericFont::System,
        },
        font_weight: font_weight.clamp(1, 1000) as u16,
        italic: flags & 2 != 0,
    };
    crate::text::ensure_face(&context);
    context.line_height = crate::text::face_line_height(&context, line_height);
    let node = tree.layout.create_text_node(Style::default(), context);
    tree.line_heights.insert(node, line_height);
    tree.owners.insert(node, unsafe { owner(h) });
    node.to_raw()
}
define_prim!(
    hlp_blinc_tree_create_text_node,
    hl_blinc_tree_create_text_node,
    "PXblinc_tree_BBffiii_l"
);

#[unsafe(no_mangle)]
pub unsafe extern "C" fn hl_blinc_tree_add_child(h: *mut c_void, parent: u64, child: u64) {
    if let Some(tree) = unsafe { tree(h) } {
        tree.layout.add_child(id(parent), id(child));
    }
}
define_prim!(
    hlp_blinc_tree_add_child,
    hl_blinc_tree_add_child,
    "PXblinc_tree_ll_v"
);

#[unsafe(no_mangle)]
pub unsafe extern "C" fn hl_blinc_tree_remove_node(h: *mut c_void, node: u64) {
    if let Some(tree) = unsafe { tree(h) } {
        forget(tree, &[id(node)]);
        tree.layout.remove_node(id(node));
        tree.props.remove(&id(node));
    }
}
define_prim!(
    hlp_blinc_tree_remove_node,
    hl_blinc_tree_remove_node,
    "PXblinc_tree_l_v"
);

#[unsafe(no_mangle)]
pub unsafe extern "C" fn hl_blinc_tree_remove_subtree(h: *mut c_void, node: u64) {
    if let Some(tree) = unsafe { tree(h) } {
        let nodes = subtree(&tree.layout, id(node));
        forget(tree, &nodes);
        tree.layout.remove_subtree(id(node));
        tree.pruned = true;
    }
}
define_prim!(
    hlp_blinc_tree_remove_subtree,
    hl_blinc_tree_remove_subtree,
    "PXblinc_tree_l_v"
);

#[unsafe(no_mangle)]
pub unsafe extern "C" fn hl_blinc_tree_clear_children(h: *mut c_void, parent: u64) {
    if let Some(tree) = unsafe { tree(h) } {
        clear_children(tree, id(parent));
    }
}
define_prim!(
    hlp_blinc_tree_clear_children,
    hl_blinc_tree_clear_children,
    "PXblinc_tree_l_v"
);

/// Put `new` where `old` is among its parent's children, leaving `old`
/// detached but not deleted. Nothing happens when `old` has no parent.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn hl_blinc_tree_replace_node(h: *mut c_void, old: u64, new: u64) {
    let Some(tree) = (unsafe { tree(h) }) else {
        return;
    };
    let (old, new) = (id(old), id(new));
    let Some(&parent) = tree.layout.ancestors(old).first() else {
        return;
    };
    let children = tree
        .layout
        .children(parent)
        .into_iter()
        .map(|child| if child == old { new } else { child })
        .collect();
    tree.layout.replace_children(parent, children);
}
define_prim!(
    hlp_blinc_tree_replace_node,
    hl_blinc_tree_replace_node,
    "PXblinc_tree_ll_v"
);

/// `children` is `len` consecutive 64-bit node ids.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn hl_blinc_tree_replace_children(
    h: *mut c_void,
    parent: u64,
    children: *const vbyte,
    len: i32,
) {
    let Some(tree) = (unsafe { tree(h) }) else {
        return;
    };
    if children.is_null() || len <= 0 {
        clear_children(tree, id(parent));
        return;
    }
    let ids = (0..len as usize)
        .map(|i| id(unsafe { (children as *const u64).add(i).read_unaligned() }))
        .collect();
    tree.layout.replace_children(id(parent), ids);
}
define_prim!(
    hlp_blinc_tree_replace_children,
    hl_blinc_tree_replace_children,
    "PXblinc_tree_lBi_v"
);

/// Writes `node`'s children as 64-bit ids into `out`, at most `capacity`.
/// Returns how many there are; 0 for a node that is gone.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn hl_blinc_tree_children(
    h: *mut c_void,
    node: u64,
    out: *mut vbyte,
    capacity: i32,
) -> i32 {
    let Some(tree) = (unsafe { tree(h) }) else {
        return 0;
    };
    if !tree.owners.contains_key(&id(node)) {
        return 0;
    }
    let ids: Vec<u64> = tree.layout.children(id(node)).iter().map(|c| c.to_raw()).collect();
    if !out.is_null() {
        let n = ids.len().min(capacity.max(0) as usize);
        unsafe { std::ptr::copy_nonoverlapping(ids.as_ptr(), out as *mut u64, n) };
    }
    ids.len() as i32
}
define_prim!(
    hlp_blinc_tree_children,
    hl_blinc_tree_children,
    "PXblinc_tree_lBi_i"
);

/// Writes `node`'s ancestors as 64-bit ids into `out`, the parent first, at
/// most `capacity`. Returns how many there are; 0 for a node that is gone or
/// has no parent.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn hl_blinc_tree_ancestors(
    h: *mut c_void,
    node: u64,
    out: *mut vbyte,
    capacity: i32,
) -> i32 {
    let Some(tree) = (unsafe { tree(h) }) else {
        return 0;
    };
    if !tree.owners.contains_key(&id(node)) {
        return 0;
    }
    let ids: Vec<u64> = tree.layout.ancestors(id(node)).iter().map(|a| a.to_raw()).collect();
    if !out.is_null() {
        let n = ids.len().min(capacity.max(0) as usize);
        unsafe { std::ptr::copy_nonoverlapping(ids.as_ptr(), out as *mut u64, n) };
    }
    ids.len() as i32
}
define_prim!(
    hlp_blinc_tree_ancestors,
    hl_blinc_tree_ancestors,
    "PXblinc_tree_lBi_i"
);

/// Makes `children`, `len` consecutive 64-bit ids, `parent`'s children in
/// that order. Children it had before and does not keep are detached, not
/// deleted, as are `children` from any other parent. A `parent` that is gone
/// is left alone, and ids of nodes that are gone are skipped: a parent's
/// removal can come before the update of what was placed in it.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn hl_blinc_tree_set_children(
    h: *mut c_void,
    parent: u64,
    children: *const vbyte,
    len: i32,
) {
    let Some(tree) = (unsafe { tree(h) }) else {
        return;
    };
    let parent = id(parent);
    if !tree.owners.contains_key(&parent) {
        return;
    }
    let ids: Vec<LayoutNodeId> = if children.is_null() || len <= 0 {
        Vec::new()
    } else {
        (0..len as usize)
            .map(|i| id(unsafe { (children as *const u64).add(i).read_unaligned() }))
            .filter(|c| tree.owners.contains_key(c))
            .collect()
    };
    // A child still listed under another parent is taken from it first.
    for &child in &ids {
        if let Some(&old) = tree.layout.ancestors(child).first() {
            if old != parent {
                let kept = tree.layout.children(old).into_iter().filter(|&c| c != child).collect();
                tree.layout.replace_children(old, kept);
            }
        }
    }
    tree.layout.replace_children(parent, ids);
}
define_prim!(
    hlp_blinc_tree_set_children,
    hl_blinc_tree_set_children,
    "PXblinc_tree_lBi_v"
);

fn drain_released_handles() -> Vec<u64> {
    std::mem::take(&mut *RELEASED_HANDLES.lock().unwrap_or_else(|e| e.into_inner()))
}

/// Remove the handle's nodes now rather than when the handle is collected,
/// with their bindings. Calls on the handle afterwards do nothing.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn hl_blinc_tree_dispose(h: *mut c_void) {
    if let Some(mut handle) = unsafe { take_handle::<TreeHandle>(h) } {
        release_handle(shared(), handle.id);
        handle.released = true;
    }
}
define_prim!(
    hlp_blinc_tree_dispose,
    hl_blinc_tree_dispose,
    "PXblinc_tree__v"
);

// ============================================================================
// FRAME
// ============================================================================

/// Apply every property write queued since the last flush, and report whether
/// any changed what is drawn: a relayout, or a visual property such as an
/// opacity or a colour, which needs a frame but no layout. Signals and computeds whose handles were
/// collected since the last flush are removed from Blinc's graph first. The
/// writes are the whole process's, applied to the one tree every handle shares.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn hl_blinc_tree_flush(h: *mut c_void) -> bool {
    let Some(tree) = (unsafe { tree(h) }) else {
        return false;
    };
    // Unbinding first frees the computeds bound only to those nodes.
    for handle in drain_released_handles() {
        release_handle(tree, handle);
    }
    collect_released();
    if std::mem::take(&mut tree.pruned) {
        let layout = &tree.layout;
        tree.props
            .retain(|node, _| layout.get_style(*node).is_some());
        tree.images
            .retain(|node, _| layout.get_style(*node).is_some());
        tree.canvases
            .retain(|node, _| layout.get_style(*node).is_some());
        tree.scrolls
            .retain(|node, _| layout.get_style(*node).is_some());
    }
    let mut needs_layout = false;
    let mut painted = false;
    for update in take_pending_partial_prop_updates() {
        let Some(mut style) = tree.layout.get_style(update.node_id) else {
            continue;
        };
        needs_layout |= update.effects.needs_layout;
        if let Some(write) = update.layout_write {
            write(&mut style);
            tree.layout.set_style(update.node_id, style);
        }
        if let Some(write) = update.render_write {
            write(tree.props.entry(update.node_id).or_default());
            painted = true;
        }
    }
    // Recorded by the render writes above, so applied after them.
    for (node, write) in take_pending_text() {
        // A line-height written is CSS's; one left alone is the one recorded.
        let css = tree.line_heights.get(&node).copied().unwrap_or(1.2);
        let mut written = css;
        needs_layout |= tree.layout.update_text(node, |c| {
            let before = c.line_height;
            write(c);
            if c.line_height != before {
                written = c.line_height;
            }
            // A new weight, style or font is loaded before layout measures with it.
            crate::text::ensure_face(c);
            c.line_height = crate::text::face_line_height(c, written);
        });
        tree.line_heights.insert(node, written);
    }
    needs_layout || painted
}
define_prim!(hlp_blinc_tree_flush, hl_blinc_tree_flush, "PXblinc_tree__b");

#[unsafe(no_mangle)]
pub unsafe extern "C" fn hl_blinc_tree_compute_layout(
    h: *mut c_void,
    root: u64,
    width: f32,
    height: f32,
) {
    if let Some(tree) = unsafe { tree(h) } {
        let space = Size {
            width: AvailableSpace::Definite(width),
            height: AvailableSpace::Definite(height),
        };
        tree.layout.compute_layout(id(root), space);
    }
}
define_prim!(
    hlp_blinc_tree_compute_layout,
    hl_blinc_tree_compute_layout,
    "PXblinc_tree_lff_v"
);

/// Pack the primitives to draw under `root` into `out` (see `display_list`), at
/// most `capacity` records. `params` is eight f32s: the device pixels per
/// layout unit text is rasterized for; the theme's corner `n` (0 for no
/// smoothing), smoothing threshold and full radius; and the colour, straight
/// RGBA, of text that neither it nor an ancestor sets; and room for a ninth,
/// where the number of records to draw is written. Returns how many records'
/// room the list takes, polygon points after the records included, which may
/// be more than were written: the caller grows its buffer and asks again.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn hl_blinc_tree_display_list(
    h: *mut c_void,
    root: u64,
    params: *const vbyte,
    out: *mut vbyte,
    capacity: i32,
) -> i32 {
    let Some(tree) = (unsafe { tree(h) }) else {
        return 0;
    };
    let p = |i: usize| -> f32 {
        if params.is_null() {
            return 0.0;
        }
        unsafe { (params as *const f32).add(i).read_unaligned() }
    };
    let display_scale = p(0);
    let shapes = crate::display_list::Shapes {
        n: p(1),
        threshold: p(2),
        radius_full: p(3),
    };
    let text_color = [p(4), p(5), p(6), p(7)];
    let mut renderer = crate::text::renderer();
    let mut records = Vec::new();
    let mut points = Vec::new();
    // A frame whose glyphs overflow the atlases starts them afresh, once.
    for _ in 0..2 {
        let mut glyphs = crate::display_list::Glyphs {
            renderer: &mut renderer,
            display_scale: if display_scale > 0.0 { display_scale } else { 1.0 },
            atlas_full: false,
            shapes,
            points: Vec::new(),
        };
        records.clear();
        crate::display_list::append(
            tree,
            id(root),
            (0.0, 0.0),
            1.0,
            text_color,
            crate::display_list::IDENTITY,
            &mut Vec::new(),
            &mut glyphs,
            &mut records,
        );
        if !glyphs.atlas_full {
            points = std::mem::take(&mut glyphs.points);
            break;
        }
        renderer.clear();
    }
    use crate::display_list::{RECORD_FLOATS, SHAPE_POLYGON};
    let drawn = records.len() / RECORD_FLOATS;
    // Polygon offsets count rows from the points' start, which is right after the records.
    let base = (drawn * RECORD_FLOATS / 4) as f32;
    for r in 0..drawn {
        if records[r * RECORD_FLOATS + 94] == SHAPE_POLYGON {
            records[r * RECORD_FLOATS + 96] += base;
        }
    }
    records.extend_from_slice(&points);
    while records.len() % RECORD_FLOATS != 0 {
        records.push(0.0);
    }
    if !params.is_null() {
        unsafe { (params as *mut f32).add(8).write_unaligned(drawn as f32) };
    }
    let count = records.len() / RECORD_FLOATS;
    let written = count.min(capacity.max(0) as usize) * crate::display_list::RECORD_FLOATS;
    if !out.is_null() && written > 0 {
        unsafe { std::ptr::copy_nonoverlapping(records.as_ptr(), out as *mut f32, written) };
    }
    count as i32
}
define_prim!(
    hlp_blinc_tree_display_list,
    hl_blinc_tree_display_list,
    "PXblinc_tree_lBBi_i"
);

/// Makes `node` draw the image the caller knows as `slot` in its content
/// box, as Blinc's image and SVG elements do; a negative `slot` stops it.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn hl_blinc_tree_set_image(h: *mut c_void, node: u64, slot: i32) {
    if let Some(tree) = unsafe { tree(h) } {
        if slot < 0 {
            tree.images.remove(&id(node));
        } else {
            tree.images.insert(id(node), slot);
        }
    }
}
define_prim!(
    hlp_blinc_tree_set_image,
    hl_blinc_tree_set_image,
    "PXblinc_tree_li_v"
);

/// Makes `node` paint itself in its content box, as the canvas the caller
/// knows as `slot`; a negative `slot` stops it.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn hl_blinc_tree_set_canvas(h: *mut c_void, node: u64, slot: i32) {
    if let Some(tree) = unsafe { tree(h) } {
        if slot < 0 {
            tree.canvases.remove(&id(node));
        } else {
            tree.canvases.insert(id(node), slot);
        }
    }
}
define_prim!(
    hlp_blinc_tree_set_canvas,
    hl_blinc_tree_set_canvas,
    "PXblinc_tree_li_v"
);

/// Write the node's absolute `x, y, width, height` as four f32s into `out`.
/// False, with `out` untouched, for a node the tree has not laid out.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn hl_blinc_tree_get_bounds(
    h: *mut c_void,
    node: u64,
    out: *mut vbyte,
) -> bool {
    let Some(tree) = (unsafe { tree(h) }) else {
        return false;
    };
    let Some(b) = tree.layout.get_absolute_bounds(id(node)) else {
        return false;
    };
    if out.is_null() {
        return false;
    }
    let out = out as *mut f32;
    for (i, v) in [b.x, b.y, b.width, b.height].into_iter().enumerate() {
        unsafe { out.add(i).write_unaligned(v) };
    }
    true
}
define_prim!(
    hlp_blinc_tree_get_bounds,
    hl_blinc_tree_get_bounds,
    "PXblinc_tree_lB_b"
);

/// Whether any of `node`'s box is on screen: inside the root and inside
/// every ancestor that clips, each scrolled and moved by its layout
/// animation as the paint walk places it. A transform on the way, which
/// can put it anywhere, counts as in view, as does a node not laid out yet;
/// a hidden ancestor, as not. A box of no size counts where it stands, so
/// one growing from nothing is seen.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn hl_blinc_tree_in_view(h: *mut c_void, node: u64) -> bool {
    let Some(tree) = (unsafe { tree(h) }) else {
        return false;
    };
    let node = id(node);
    let mut path = tree.layout.ancestors(node);
    path.reverse();
    path.push(node);
    // The visible rect so far, in the root's coordinates, and where the next node's parent puts its children.
    let mut clip = [f32::NEG_INFINITY, f32::NEG_INFINITY, f32::INFINITY, f32::INFINITY];
    let mut origin = (0.0f32, 0.0f32);
    for (i, &n) in path.iter().enumerate() {
        let Some(layout) = tree.layout.get_layout(n) else {
            return true;
        };
        let mut x = origin.0 + layout.location.x;
        let mut y = origin.1 + layout.location.y;
        let (mut w, mut h) = (layout.size.width, layout.size.height);
        if let Some(v) = tree.visuals.get(&n) {
            x += v[0];
            y += v[1];
            if v[2] >= 0.0 {
                (w, h) = (v[2], v[3].max(0.0));
            }
        }
        if let Some(p) = tree.props.get(&n) {
            if !p.visible {
                return false;
            }
            if p.transform.is_some() {
                return true;
            }
        }
        let clips = i == 0 || tree.layout.get_style(n).is_some_and(|s| s.overflow.x != taffy::Overflow::Visible || s.overflow.y != taffy::Overflow::Visible);
        if clips {
            clip = [clip[0].max(x), clip[1].max(y), clip[2].min(x + w), clip[3].min(y + h)];
        }
        if i == path.len() - 1 {
            return x <= clip[2] && x + w >= clip[0] && y <= clip[3] && y + h >= clip[1] && clip[0] <= clip[2] && clip[1] <= clip[3];
        }
        let (sx, sy) = tree.scrolls.get(&n).map_or((0.0, 0.0), |s| (s.x, s.y));
        origin = (x - sx, y - sy);
    }
    true
}
define_prim!(hlp_blinc_tree_in_view, hl_blinc_tree_in_view, "PXblinc_tree_l_b");

/// `node`'s padding as laid out, top, right, bottom, left, then 1 if it
/// paints a box of its own (a background, a border or a shadow) and 0 if not,
/// as five f32s in `out`. False when it has no layout.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn hl_blinc_tree_box_edges(h: *mut c_void, node: u64, out: *mut vbyte) -> bool {
    let Some(tree) = (unsafe { tree(h) }) else {
        return false;
    };
    let Some(layout) = tree.layout.get_layout(id(node)) else {
        return false;
    };
    if out.is_null() {
        return false;
    }
    let p = layout.padding;
    let painted = tree.props.get(&id(node)).is_some_and(|r| {
        let visible_bg = match &r.background {
            Some(blinc_core::Brush::Solid(c)) => c.a > 0.0,
            Some(_) => true,
            None => false,
        };
        let sides = &r.border_sides;
        let border = r.border_width > 0.0 || [&sides.top, &sides.right, &sides.bottom, &sides.left].iter().any(|s| s.as_ref().is_some_and(|s| s.width > 0.0));
        visible_bg || border || !r.shadow.is_empty() || !r.inner_shadow.is_empty()
    });
    let out = out as *mut f32;
    for (i, v) in [p.top, p.right, p.bottom, p.left, if painted { 1.0 } else { 0.0 }].into_iter().enumerate() {
        unsafe { out.add(i).write_unaligned(v) };
    }
    true
}
define_prim!(hlp_blinc_tree_box_edges, hl_blinc_tree_box_edges, "PXblinc_tree_lB_b");

/// `node`'s own text alignment, 0 left, 1 centre, 2 right, as `ashui.types.Style.TextAlign`; -1 when it has none.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn hl_blinc_tree_text_align(h: *mut c_void, node: u64) -> i32 {
    let Some(tree) = (unsafe { tree(h) }) else {
        return -1;
    };
    match tree.props.get(&id(node)).and_then(|p| p.text_align) {
        Some(blinc_layout::div::TextAlign::Left) => 0,
        Some(blinc_layout::div::TextAlign::Center) => 1,
        Some(blinc_layout::div::TextAlign::Right) => 2,
        None => -1,
    }
}
define_prim!(hlp_blinc_tree_text_align, hl_blinc_tree_text_align, "PXblinc_tree_l_i");

/// Draws `node` as a notch, from twelve f32s in `data`: its corner radii,
/// top-left, top-right, bottom-right, bottom-left, each negative for a
/// concave corner, then its top and bottom edges, each (kind, width, height,
/// corner radius) with kind 0 none, 1 scoop, 2 bulge, 3 cut, 4 peak. A null
/// `data` draws it as a box again.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn hl_blinc_tree_set_notch(h: *mut c_void, node: u64, data: *const vbyte) {
    let Some(tree) = (unsafe { tree(h) }) else {
        return;
    };
    if data.is_null() {
        tree.notches.remove(&id(node));
        return;
    }
    let f = data as *const f32;
    let mut rows = [[0.0f32; 4]; 3];
    for (i, row) in rows.iter_mut().enumerate() {
        for (j, v) in row.iter_mut().enumerate() {
            *v = unsafe { f.add(i * 4 + j).read_unaligned() };
        }
    }
    tree.notches.insert(id(node), rows);
}
define_prim!(hlp_blinc_tree_set_notch, hl_blinc_tree_set_notch, "PXblinc_tree_lB_v");

/// Draws `node` moved by `(dx, dy)` from its layout, and at size `(w, h)`
/// with its children clipped to it when `w` is not negative, as a layout
/// animation does; its children move with it, and the hit test follows.
/// `clear` draws it at its layout again.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn hl_blinc_tree_set_visual(h: *mut c_void, node: u64, dx: f32, dy: f32, w: f32, hh: f32, clear: bool) {
    let Some(tree) = (unsafe { tree(h) }) else {
        return;
    };
    if clear {
        tree.visuals.remove(&id(node));
    } else {
        tree.visuals.insert(id(node), [dx, dy, w, hh]);
    }
}
define_prim!(hlp_blinc_tree_set_visual, hl_blinc_tree_set_visual, "PXblinc_tree_lffffb_v");

/// Makes the hit test pass through `node` and everything inside it, or not.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn hl_blinc_tree_set_pass_through(h: *mut c_void, node: u64, through: bool) {
    if let Some(tree) = unsafe { tree(h) } {
        if through {
            tree.pass_through.insert(id(node));
        } else {
            tree.pass_through.remove(&id(node));
        }
    }
}
define_prim!(hlp_blinc_tree_set_pass_through, hl_blinc_tree_set_pass_through, "PXblinc_tree_lb_v");

/// Scrolls container `node`'s content by `(x, y)` and colours its thumb
/// `thumb`, `0xAARRGGBB` (0 hides it), as Blinc's scroll containers do.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn hl_blinc_tree_set_scroll(h: *mut c_void, node: u64, x: f32, y: f32, thumb: i32) {
    if let Some(tree) = unsafe { tree(h) } {
        let c = |shift: i32| ((thumb >> shift) & 0xff) as f32 / 255.0;
        tree.scrolls.insert(
            id(node),
            Scroll {
                x,
                y,
                thumb: [c(16), c(8), c(0), c(24)],
            },
        );
    }
}
define_prim!(
    hlp_blinc_tree_set_scroll,
    hl_blinc_tree_set_scroll,
    "PXblinc_tree_lffi_v"
);

/// Writes container `node`'s viewport width and height (inside its border)
/// and its content's width and height as four f32s into `out`; false before
/// it is laid out.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn hl_blinc_tree_scroll_extent(h: *mut c_void, node: u64, out: *mut vbyte) -> bool {
    let Some(tree) = (unsafe { tree(h) }) else {
        return false;
    };
    let Some(layout) = tree.layout.get_layout(id(node)) else {
        return false;
    };
    if out.is_null() {
        return false;
    }
    let b = layout.border;
    let view = (
        layout.size.width - b.left - b.right,
        layout.size.height - b.top - b.bottom,
    );
    let out = out as *mut f32;
    for (i, v) in [view.0, view.1, layout.content_size.width, layout.content_size.height]
        .into_iter()
        .enumerate()
    {
        unsafe { out.add(i).write_unaligned(v) };
    }
    true
}
define_prim!(
    hlp_blinc_tree_scroll_extent,
    hl_blinc_tree_scroll_extent,
    "PXblinc_tree_lB_b"
);
