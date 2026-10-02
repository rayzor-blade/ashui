//! The layout tree as a Haxe handle, and the per-frame steps that drive it:
//! applying queued property writes, computing layout, reading bounds.

use crate::hl::{handle_mut, into_handle, opt_string_from, string_from, take_handle};
use crate::layout_router::take_pending_text;
use crate::reactive::collect_released;
use blinc_layout::binding::unregister_node;
use blinc_layout::div::GenericFont;
use blinc_layout::element::RenderProps;
use blinc_layout::stateful::take_pending_partial_prop_updates;
use blinc_layout::tree::{LayoutNodeId, LayoutTree, TextMeasureContext};
use hl_abi::{define_prim, vbyte};
use std::collections::{HashMap, HashSet};
use std::ffi::c_void;
use std::sync::Mutex;
use taffy::prelude::{AvailableSpace, Size, Style};

pub struct Tree {
    layout: LayoutTree,
    /// Visual properties per node; `LayoutTree` holds only styles.
    props: HashMap<LayoutNodeId, RenderProps>,
    /// Set by removals, so the next flush drops props of nodes now gone.
    pruned: bool,
    /// Every live node, so a dropped tree can drop their bindings.
    nodes: HashSet<LayoutNodeId>,
}

/// Nodes of trees dropped since the last flush, whose bindings are still
/// registered. A tree may be dropped by its finalizer, inside a collection,
/// where taking the binding registry's lock is not safe, so the next flush
/// unbinds them. Until then, a later tree reusing an id could receive a write
/// meant for the dropped node; disposing a tree unbinds at once instead.
static RELEASED_NODES: Mutex<Vec<LayoutNodeId>> = Mutex::new(Vec::new());

impl Drop for Tree {
    fn drop(&mut self) {
        RELEASED_NODES
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .extend(self.nodes.drain());
    }
}

/// # Safety
/// `h` must be null or a `blinc_tree` handle.
unsafe fn tree<'a>(h: *mut c_void) -> Option<&'a mut Tree> {
    unsafe { handle_mut::<Tree>(h) }
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
        tree.nodes.remove(node);
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

#[unsafe(no_mangle)]
pub extern "C" fn hl_blinc_tree_new() -> *mut c_void {
    into_handle(Tree {
        layout: LayoutTree::new(),
        props: HashMap::new(),
        pruned: false,
        nodes: HashSet::new(),
    })
}
define_prim!(hlp_blinc_tree_new, hl_blinc_tree_new, "P_Xblinc_tree_");

#[unsafe(no_mangle)]
pub unsafe extern "C" fn hl_blinc_tree_create_node(h: *mut c_void) -> u64 {
    let Some(tree) = (unsafe { tree(h) }) else {
        return 0;
    };
    let node = tree.layout.create_node(Style::default());
    tree.nodes.insert(node);
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
    tree.nodes.insert(node);
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

fn drain_released_nodes() -> Vec<LayoutNodeId> {
    std::mem::take(&mut *RELEASED_NODES.lock().unwrap_or_else(|e| e.into_inner()))
}

/// Free the tree now rather than when its handle is collected, dropping its
/// nodes' bindings. Calls on the handle afterwards do nothing.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn hl_blinc_tree_dispose(h: *mut c_void) {
    if let Some(mut tree) = unsafe { take_handle::<Tree>(h) } {
        let nodes: Vec<_> = tree.nodes.iter().copied().collect();
        forget(&mut tree, &nodes);
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
/// any of them needs a relayout. Signals and computeds whose handles were
/// collected since the last flush are removed from Blinc's graph first.
///
/// Blinc keeps one queue for the process and node ids are only unique within
/// a tree, so this assumes the program has a single tree.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn hl_blinc_tree_flush(h: *mut c_void) -> bool {
    let Some(tree) = (unsafe { tree(h) }) else {
        return false;
    };
    // Unbinding first frees the computeds bound only to those nodes.
    for node in drain_released_nodes() {
        unregister_node(node);
    }
    collect_released();
    if std::mem::take(&mut tree.pruned) {
        let layout = &tree.layout;
        tree.props
            .retain(|node, _| layout.get_style(*node).is_some());
    }
    let mut needs_layout = false;
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
        }
    }
    // Recorded by the render writes above, so applied after them.
    for (node, write) in take_pending_text() {
        needs_layout |= tree.layout.update_text(node, write);
    }
    needs_layout
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
