use hl_abi::define_prim;
use std::ffi::CStr;
use std::sync::Arc;
use taffy::prelude::*;

use blinc_core::reactive::{Computed, State};
use blinc_core::{Brush, Color, CornerRadius as BorderRadius, Transform};
use blinc_layout::binding::{
    register_typed, register_typed_computed, register_typed_layout, register_typed_layout_computed,
};
use blinc_layout::element::RenderProps;
use blinc_core::layer::Shadow;
use blinc_layout::property::PropertyId;
use blinc_layout::stateful::{queue_layout_update_partial, queue_prop_update_partial};
use blinc_layout::tree::LayoutNodeId;

// ============================================================================
// 1. CORE ROUTING HELPERS
// ============================================================================

fn apply_reactive_layout<T: Clone + Send + Sync + 'static>(
    node_id: LayoutNodeId,
    prop_id: PropertyId,
    kind: u8,
    const_val: T,
    state_ptr: *const State<T>,
    comp_ptr: *const Computed<T>,
    write: impl Fn(&mut taffy::Style, T) + Send + Sync + 'static,
) {
    let write_arc = Arc::new(write);

    match kind {
        0 => {
            let w = Arc::clone(&write_arc);
            queue_layout_update_partial(node_id, prop_id, prop_id.side_effects(), move |s| {
                w(s, const_val)
            });
        }
        1 => {
            let state = unsafe { &*state_ptr }.clone();
            let w = Arc::clone(&write_arc);
            register_typed_layout(state.signal_id(), node_id, prop_id, state, move |s, v| {
                w(s, v)
            });
        }
        2 => {
            let comp = unsafe { &*comp_ptr }.clone();
            let w = Arc::clone(&write_arc);
            register_typed_layout_computed(
                comp.derived_id(),
                node_id,
                prop_id,
                comp,
                move |s, v| w(s, v),
            );
        }
        _ => {}
    }
}

fn apply_reactive_render<T: Clone + Send + Sync + 'static>(
    node_id: LayoutNodeId,
    prop_id: PropertyId,
    kind: u8,
    const_val: T,
    state_ptr: *const State<T>,
    comp_ptr: *const Computed<T>,
    write: impl Fn(&mut RenderProps, T) + Send + Sync + 'static,
) {
    let write_arc = Arc::new(write);

    match kind {
        0 => {
            let w = Arc::clone(&write_arc);
            queue_prop_update_partial(node_id, prop_id, prop_id.side_effects(), move |p| {
                w(p, const_val)
            });
        }
        1 => {
            let state = unsafe { &*state_ptr }.clone();
            let w = Arc::clone(&write_arc);
            register_typed(state.signal_id(), node_id, prop_id, state, move |p, v| {
                w(p, v)
            });
        }
        2 => {
            let comp = unsafe { &*comp_ptr }.clone();
            let w = Arc::clone(&write_arc);
            register_typed_computed(comp.derived_id(), node_id, prop_id, comp, move |p, v| {
                w(p, v)
            });
        }
        _ => {}
    }
}

// ============================================================================
// 2. THE FLOAT (F32) ROUTER - Layout Dimensions & Visual Floats
// ============================================================================

#[unsafe(no_mangle)]
pub unsafe extern "C" fn hl_blinc_apply_f32(
    node_raw: u64,
    prop_raw: u32,
    kind: u8,
    val_const: f32,
    state_ptr: *const State<f32>,
    comp_ptr: *const Computed<f32>,
) {
    let node_id = LayoutNodeId::from_raw(node_raw);
    let prop_id: PropertyId = unsafe { std::mem::transmute(prop_raw as u8) };

    match prop_id {
        // --- Layout Properties (Tier 2) ---
        PropertyId::Width => apply_reactive_layout(
            node_id,
            prop_id,
            kind,
            val_const,
            state_ptr,
            comp_ptr,
            |s, v| s.size.width = Dimension::Length(v),
        ),
        PropertyId::Height => apply_reactive_layout(
            node_id,
            prop_id,
            kind,
            val_const,
            state_ptr,
            comp_ptr,
            |s, v| s.size.height = Dimension::Length(v),
        ),
        PropertyId::MinWidth => apply_reactive_layout(
            node_id,
            prop_id,
            kind,
            val_const,
            state_ptr,
            comp_ptr,
            |s, v| s.min_size.width = Dimension::Length(v),
        ),
        PropertyId::MaxWidth => apply_reactive_layout(
            node_id,
            prop_id,
            kind,
            val_const,
            state_ptr,
            comp_ptr,
            |s, v| s.max_size.width = Dimension::Length(v),
        ),
        PropertyId::MinHeight => apply_reactive_layout(
            node_id,
            prop_id,
            kind,
            val_const,
            state_ptr,
            comp_ptr,
            |s, v| s.min_size.height = Dimension::Length(v),
        ),
        PropertyId::MaxHeight => apply_reactive_layout(
            node_id,
            prop_id,
            kind,
            val_const,
            state_ptr,
            comp_ptr,
            |s, v| s.max_size.height = Dimension::Length(v),
        ),
        PropertyId::FlexBasis => apply_reactive_layout(
            node_id,
            prop_id,
            kind,
            val_const,
            state_ptr,
            comp_ptr,
            |s, v| s.flex_basis = Dimension::Length(v),
        ),
        PropertyId::FlexGrow => apply_reactive_layout(
            node_id,
            prop_id,
            kind,
            val_const,
            state_ptr,
            comp_ptr,
            |s, v| s.flex_grow = v,
        ),
        PropertyId::FlexShrink => apply_reactive_layout(
            node_id,
            prop_id,
            kind,
            val_const,
            state_ptr,
            comp_ptr,
            |s, v| s.flex_shrink = v,
        ),

        PropertyId::Padding => apply_reactive_layout(
            node_id,
            prop_id,
            kind,
            val_const,
            state_ptr,
            comp_ptr,
            |s, v| {
                let pad = LengthPercentage::Length(v);
                s.padding.left = pad;
                s.padding.right = pad;
                s.padding.top = pad;
                s.padding.bottom = pad;
            },
        ),
        PropertyId::Margin => apply_reactive_layout(
            node_id,
            prop_id,
            kind,
            val_const,
            state_ptr,
            comp_ptr,
            |s, v| {
                let margin = LengthPercentageAuto::Length(v);
                s.margin.left = margin;
                s.margin.right = margin;
                s.margin.top = margin;
                s.margin.bottom = margin;
            },
        ),
        PropertyId::Gap => apply_reactive_layout(
            node_id,
            prop_id,
            kind,
            val_const,
            state_ptr,
            comp_ptr,
            |s, v| {
                s.gap.width = LengthPercentage::Length(v);
                s.gap.height = LengthPercentage::Length(v);
            },
        ),

        PropertyId::Top => apply_reactive_layout(
            node_id,
            prop_id,
            kind,
            val_const,
            state_ptr,
            comp_ptr,
            |s, v| s.inset.top = LengthPercentageAuto::Length(v),
        ),
        PropertyId::Right => apply_reactive_layout(
            node_id,
            prop_id,
            kind,
            val_const,
            state_ptr,
            comp_ptr,
            |s, v| s.inset.right = LengthPercentageAuto::Length(v),
        ),
        PropertyId::Bottom => apply_reactive_layout(
            node_id,
            prop_id,
            kind,
            val_const,
            state_ptr,
            comp_ptr,
            |s, v| s.inset.bottom = LengthPercentageAuto::Length(v),
        ),
        PropertyId::Left => apply_reactive_layout(
            node_id,
            prop_id,
            kind,
            val_const,
            state_ptr,
            comp_ptr,
            |s, v| s.inset.left = LengthPercentageAuto::Length(v),
        ),

        // --- Visual Properties (Tier 1) ---
        PropertyId::Opacity => apply_reactive_render(
            node_id,
            prop_id,
            kind,
            val_const,
            state_ptr,
            comp_ptr,
            |p, v| p.opacity = v,
        ),
        PropertyId::BorderWidth => apply_reactive_render(
            node_id,
            prop_id,
            kind,
            val_const,
            state_ptr,
            comp_ptr,
            |p, v| p.border_width = v,
        ),

        // --- Text Properties ---
        PropertyId::FontSize => apply_reactive_render(
            node_id,
            prop_id,
            kind,
            val_const,
            state_ptr,
            comp_ptr,
            |p, v| p.font_size = Some(v),
        ),
        PropertyId::LetterSpacing => apply_reactive_render(
            node_id,
            prop_id,
            kind,
            val_const,
            state_ptr,
            comp_ptr,
            |p, v| p.letter_spacing = Some(v),
        ),
        PropertyId::LineHeight => apply_reactive_render(
            node_id,
            prop_id,
            kind,
            val_const,
            state_ptr,
            comp_ptr,
            |p, v| p.line_height = Some(v),
        ),

        _ => {}
    }
}
define_prim!(hlp_blinc_apply_f32, hl_blinc_apply_f32, "V_I64IIFPP");

// ============================================================================
// 3. THE INTEGER (I32) ROUTER - Solid Colors & Enums
// ============================================================================

#[unsafe(no_mangle)]
pub unsafe extern "C" fn hl_blinc_apply_i32(
    node_raw: u64,
    prop_raw: u32,
    kind: u8,
    val_const: i32,
    state_ptr: *const State<i32>,
    comp_ptr: *const Computed<i32>,
) {
    let node_id = LayoutNodeId::from_raw(node_raw);
    let prop_id: PropertyId = unsafe { std::mem::transmute(prop_raw as u8) };

    match prop_id {

        // --- Layout Enums (Transmuted to Taffy types) ---
        PropertyId::FlexDirection => apply_reactive_layout(
            node_id,
            prop_id,
            kind,
            val_const,
            state_ptr,
            comp_ptr,
            |s, v| s.flex_direction = unsafe { std::mem::transmute(v as u8) },
        ),
        PropertyId::AlignItems => apply_reactive_layout(
            node_id,
            prop_id,
            kind,
            val_const,
            state_ptr,
            comp_ptr,
            |s, v| s.align_items = Some(unsafe { std::mem::transmute(v as u8) }),
        ),
        PropertyId::JustifyContent => apply_reactive_layout(
            node_id,
            prop_id,
            kind,
            val_const,
            state_ptr,
            comp_ptr,
            |s, v| s.justify_content = Some(unsafe { std::mem::transmute(v as u8) }),
        ),
        PropertyId::AlignSelf => apply_reactive_layout(
            node_id,
            prop_id,
            kind,
            val_const,
            state_ptr,
            comp_ptr,
            |s, v| s.align_self = Some(unsafe { std::mem::transmute(v as u8) }),
        ),
        PropertyId::FlexWrap => apply_reactive_layout(
            node_id,
            prop_id,
            kind,
            val_const,
            state_ptr,
            comp_ptr,
            |s, v| s.flex_wrap = unsafe { std::mem::transmute(v as u8) },
        ),
        PropertyId::Display => apply_reactive_layout(
            node_id,
            prop_id,
            kind,
            val_const,
            state_ptr,
            comp_ptr,
            |s, v| s.display = unsafe { std::mem::transmute(v as u8) },
        ),
        PropertyId::Position => apply_reactive_layout(
            node_id,
            prop_id,
            kind,
            val_const,
            state_ptr,
            comp_ptr,
            |s, v| s.position = unsafe { std::mem::transmute(v as u8) },
        ),
        PropertyId::Overflow => apply_reactive_layout(
            node_id,
            prop_id,
            kind,
            val_const,
            state_ptr,
            comp_ptr,
            |s, v| {
                let overflow_val: taffy::style::Overflow = unsafe { std::mem::transmute(v as u8) };
                s.overflow.x = overflow_val;
                s.overflow.y = overflow_val;
            },
        ),

        // --- Text Enums ---
        PropertyId::FontWeight => apply_reactive_render(
            node_id,
            prop_id,
            kind,
            val_const,
            state_ptr,
            comp_ptr,
            |p, v| p.font_weight = Some(unsafe { std::mem::transmute(v as u8) }),
        ),
        PropertyId::FontStyle => apply_reactive_render(
            node_id,
            prop_id,
            kind,
            val_const,
            state_ptr,
            comp_ptr,
            |p, v| p.font_style = Some(unsafe { std::mem::transmute(v as u8) }),
        ),
        PropertyId::TextAlign => apply_reactive_render(
            node_id,
            prop_id,
            kind,
            val_const,
            state_ptr,
            comp_ptr,
            |p, v| p.text_align = Some(unsafe { std::mem::transmute(v as u8) }),
        ),

        _ => {}
    }
}
define_prim!(hlp_blinc_apply_i32, hl_blinc_apply_i32, "V_I64IIIPP");

// ============================================================================
// 4. COMPLEX METADATA ROUTERS (Pointers for Brushes, Transforms, Shadows)
// ============================================================================

macro_rules! hl_export_complex_router {
    ($fn_name:ident, $prim_name:ident, $type:ty, $prop_id_match:pat, $render_mutation:expr) => {
        #[unsafe(no_mangle)]
        pub unsafe extern "C" fn $fn_name(
            node_raw: u64, prop_raw: u32, kind: u8,
            val_ptr: *mut $type,
            state_ptr: *const State<$type>,
            comp_ptr: *const Computed<$type>,
        ) {
            let node_id = LayoutNodeId::from_raw(node_raw);
            let prop_id: PropertyId = unsafe { std::mem::transmute(prop_raw as u8) };
            
            if !matches!(prop_id, $prop_id_match) { return; }

            let const_val = if kind == 0 && !val_ptr.is_null() {
                unsafe { (*val_ptr).clone() }
            } else {
                return; // Fallback for invalid const pointer
            };

            // Pass prop_id into the apply_reactive_render closure
            apply_reactive_render(
                node_id, prop_id, kind, const_val, state_ptr, comp_ptr, 
                move |props, val| $render_mutation(props, val, prop_id)
            );
        }
        define_prim!($prim_name, $fn_name, "V_I64IIPPP");
    };
}

// Complex Brush Router (Enables GlassStyle, Gradients, Images, etc.)
// Mapped to Background
hl_export_complex_router!(
    hl_blinc_apply_brush, hlp_blinc_apply_brush, Brush,
    PropertyId::Background,
    |p: &mut RenderProps, v, _prop| p.background = Some(v)
);

hl_export_complex_router!(
    hl_blinc_apply_color, hlp_blinc_apply_color, Color,
    PropertyId::BorderColor | PropertyId::Color | PropertyId::AccentColor,
    |p: &mut RenderProps, v: Color, prop| {
        match prop {
            PropertyId::BorderColor => p.border_color = Some(v),
            PropertyId::Color => p.text_color = Some(v.to_array()),
            PropertyId::AccentColor => p.outline_color = Some(v),
            _ => {}
        }
    }
);

hl_export_complex_router!(
    hl_blinc_apply_corner_radius, hlp_blinc_apply_corner_radius, BorderRadius,
    PropertyId::CornerRadius,
    |p: &mut RenderProps, v, _prop| {
        p.border_radius = v;
        p.border_radius_explicit = true;
    }
);

// Complex Transform Router
// Mapped to Transform
hl_export_complex_router!(
    hl_blinc_apply_transform,
    hlp_blinc_apply_transform,
    Transform,
    PropertyId::Transform,
    |p: &mut RenderProps, v, _prop| p.transform = Some(v)
);

// Complex Shadow Router
// Mapped to Shadow (Allows Vec of layered drop shadows)
hl_export_complex_router!(
    hl_blinc_apply_shadow,
    hlp_blinc_apply_shadow,
    Vec<Shadow>,
    PropertyId::Shadow,
    |p: &mut RenderProps, v, _prop| p.shadow = v
);


#[unsafe(no_mangle)]
pub unsafe extern "C" fn hl_blinc_apply_string(
    node_raw: u64, prop_raw: u32, kind: u8,
    val_ptr: *const std::ffi::c_char,
    state_ptr: *const State<String>,
    comp_ptr: *const Computed<String>,
) {
    let node_id = LayoutNodeId::from_raw(node_raw);
    let prop_id: PropertyId = unsafe { std::mem::transmute(prop_raw as u8) };
    
    // Unpack constant string safely from raw bytes if kind == 0
    let const_val = if kind == 0 && !val_ptr.is_null() {
        let c_str = unsafe { CStr::from_ptr(val_ptr) };
        c_str.to_string_lossy().into_owned()
    } else if kind == 0 {
        String::new()
    } else {
        String::new() // Dummy value when bound to state/computed
    };

    apply_reactive_render(
        node_id, prop_id, kind, const_val, state_ptr, comp_ptr,
        move |p: &mut RenderProps, v| {
            match prop_id {
                PropertyId::FontFamily => {
                    // Map to your RenderProps or text style configuration fields if applicable
                }
                PropertyId::TextContent => {
                    // Dynamic text content updates
                }
                _ => {}
            }
        }
    );
}
// Signature: V_I64IIPPP (NodeId, PropId, Kind, ValPtr, StatePtr, CompPtr)
define_prim!(hlp_blinc_apply_string, hl_blinc_apply_string, "V_I64IIPPP");

