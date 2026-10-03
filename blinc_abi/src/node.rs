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
use blinc_layout::init_text_measurer;
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
    /// Scroll containers: how far their content is scrolled, and their thumb.
    pub(crate) scrolls: HashMap<LayoutNodeId, Scroll>,
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
            scrolls: HashMap::new(),
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
    TEXT_MEASURER.call_once(init_text_measurer);
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
    let context = TextMeasureContext {
        content: unsafe { string_from(content) },
        font_size,
        line_height,
        wrap: flags & 1 != 0,
        font_name: unsafe { opt_string_from(font_name) },
        generic_font: match generic_font {
            1 => GenericFont::Monospace,
            2 => GenericFont::Serif,
            3 => GenericFont::SansSerif,
            _ => GenericFont::System,
        },
        font_weight: font_weight.clamp(1, 1000) as u16,
        italic: flags & 2 != 0,
    };
    let node = tree.layout.create_text_node(Style::default(), context);
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
        needs_layout |= tree.layout.update_text(node, write);
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
/// RGBA, of text that neither it nor an ancestor sets. Returns how many
/// records there are, which may be more than were written: the caller grows
/// its buffer and asks again.
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
    // A frame whose glyphs overflow the atlases starts them afresh, once.
    for _ in 0..2 {
        let mut glyphs = crate::display_list::Glyphs {
            renderer: &mut renderer,
            display_scale: if display_scale > 0.0 { display_scale } else { 1.0 },
            atlas_full: false,
            shapes,
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
            break;
        }
        renderer.clear();
    }
    let count = records.len() / crate::display_list::RECORD_FLOATS;
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
