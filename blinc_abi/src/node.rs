

use hl_abi::define_prim;
use std::ffi::CStr;
use taffy::prelude::Style;
use blinc_layout::tree::{LayoutTree, LayoutNodeId, TextMeasureContext};

// ============================================================================
// TREE LIFECYCLE
// ============================================================================

#[unsafe(no_mangle)]
pub unsafe extern "C" fn hl_blinc_tree_new() -> *mut LayoutTree {
    Box::into_raw(Box::new(LayoutTree::new()))
}
define_prim!(hlp_blinc_tree_new, hl_blinc_tree_new, "P_V");

#[unsafe(no_mangle)]
pub unsafe extern "C" fn hl_blinc_tree_drop(tree: *mut LayoutTree) {
    if !tree.is_null() {
        unsafe { let _ = Box::from_raw(tree); }
    }
}
define_prim!(hlp_blinc_tree_drop, hl_blinc_tree_drop, "V_P");

// ============================================================================
// NODE CREATION
// ============================================================================

#[unsafe(no_mangle)]
pub unsafe extern "C" fn hl_blinc_tree_create_node(tree: *mut LayoutTree) -> u64 {
    let tree = unsafe { &mut *tree };
    // Node is created with default style; reactive properties will mutate it later
    tree.create_node(Style::default()).to_raw()
}
define_prim!(hlp_blinc_tree_create_node, hl_blinc_tree_create_node, "I64_P");

#[unsafe(no_mangle)]
pub unsafe extern "C" fn hl_blinc_tree_create_text_node(
    tree: *mut LayoutTree,
    content_ptr: *const std::ffi::c_char,
    font_size: f32,
    line_height: f32,
    wrap: bool,
    font_name_ptr: *const std::ffi::c_char,
    generic_font_raw: u8,
    font_weight: u16,
    italic: bool,
) -> u64 {
    let tree = unsafe { &mut *tree };
    
    let content = if content_ptr.is_null() {
        String::new()
    } else {
        CStr::from_ptr(content_ptr).to_string_lossy().into_owned()
    };

    let font_name = if font_name_ptr.is_null() {
        None
    } else {
        Some(CStr::from_ptr(font_name_ptr).to_string_lossy().into_owned())
    };

    let context = TextMeasureContext {
        content,
        font_size,
        line_height,
        wrap,
        font_name,
        generic_font: unsafe { std::mem::transmute(generic_font_raw) },
        font_weight,
        italic,
    };

    tree.create_text_node(Style::default(), context).to_raw()
}
// Returns I64, Takes Pointer(Tree), Pointer(String), Float, Float, Bool, Pointer(String), Int, Int, Bool
define_prim!(hlp_blinc_tree_create_text, hl_blinc_tree_create_text_node, "I64_PPFFBPIIB");

// ============================================================================
// TREE MUTATION (MOUNTING & DIFFING)
// ============================================================================

#[unsafe(no_mangle)]
pub unsafe extern "C" fn hl_blinc_tree_add_child(tree: *mut LayoutTree, parent: u64, child: u64) {
    let tree = unsafe { &mut *tree };
    tree.add_child(LayoutNodeId::from_raw(parent), LayoutNodeId::from_raw(child));
}
define_prim!(hlp_blinc_tree_add_child, hl_blinc_tree_add_child, "V_PI64I64");

#[unsafe(no_mangle)]
pub unsafe extern "C" fn hl_blinc_tree_remove_node(tree: *mut LayoutTree, node: u64) {
    let tree = unsafe { &mut *tree };
    tree.remove_node(LayoutNodeId::from_raw(node));
}
define_prim!(hlp_blinc_tree_remove_node, hl_blinc_tree_remove_node, "V_PI64");

#[unsafe(no_mangle)]
pub unsafe extern "C" fn hl_blinc_tree_remove_subtree(tree: *mut LayoutTree, node: u64) {
    let tree = unsafe { &mut *tree };
    tree.remove_subtree(LayoutNodeId::from_raw(node));
}
define_prim!(hlp_blinc_tree_remove_subtree, hl_blinc_tree_remove_subtree, "V_PI64");

#[unsafe(no_mangle)]
pub unsafe extern "C" fn hl_blinc_tree_clear_children(tree: *mut LayoutTree, parent: u64) {
    let tree = unsafe { &mut *tree };
    tree.clear_children(LayoutNodeId::from_raw(parent));
}
define_prim!(hlp_blinc_tree_clear_children, hl_blinc_tree_clear_children, "V_PI64");

#[unsafe(no_mangle)]
pub unsafe extern "C" fn hl_blinc_tree_replace_children(
    tree: *mut LayoutTree, 
    parent: u64, 
    children_ptr: *const u64, 
    children_len: i32
) {
    let tree = unsafe { &mut *tree };
    if children_ptr.is_null() || children_len <= 0 {
        tree.clear_children(LayoutNodeId::from_raw(parent));
        return;
    }
    
    let slice = unsafe { std::slice::from_raw_parts(children_ptr, children_len as usize) };
    let new_children: Vec<LayoutNodeId> = slice.iter().map(|&id| LayoutNodeId::from_raw(id)).collect();
    
    tree.replace_children(LayoutNodeId::from_raw(parent), new_children);
}
define_prim!(hlp_blinc_tree_replace_children, hl_blinc_tree_replace_children, "V_PI64PI");