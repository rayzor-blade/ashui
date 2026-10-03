//! Binding node properties to constants, signals and computeds.
//!
//! Every router takes `kind`: 0 applies the constant argument, 1 binds the
//! signal handle, 2 binds the computed handle. A binding also applies its
//! current value at once, because Blinc's bindings only write on change.
//! Writes are queued; `blinc_tree_flush` applies them.
//!
//! Enum-valued properties use the integer codes of the Haxe enum abstracts in
//! `ashui.types.Style`. Codes out of range fall back to the property's default.
//!
//! Properties a text node is measured by also change its measure context.
//! Blinc's queue carries only render and layout writes, so those bindings
//! record the change here and `blinc_tree_flush` applies it through
//! `LayoutTree::update_text`.

use crate::hl::{handle_ref, opt_string_from};
use crate::reactive::{AnyComputed, AnySignal, Slot};
use crate::types::Value;
use blinc_core::CornerShape;
use blinc_layout::binding::{
    register_typed, register_typed_computed, register_typed_layout, register_typed_layout_computed,
};
use blinc_layout::div::{FontWeight, TextAlign};
use blinc_layout::element::RenderProps;
use blinc_layout::element_style::FontStyle;
use blinc_layout::property::PropertyId;
use blinc_layout::stateful::{queue_layout_update_partial, queue_prop_update_partial};
use blinc_layout::tree::{LayoutNodeId, TextMeasureContext};
use hl_abi::{define_prim, vbyte};
use std::ffi::c_void;
use std::sync::{Arc, Mutex};
use taffy::prelude::*;
use taffy::{Overflow, Point};

const KIND_CONST: i32 = 0;
const KIND_SIGNAL: i32 = 1;
const KIND_COMPUTED: i32 = 2;

/// `PropertyId` in declaration order, which `ashui.layout.PropertyId` mirrors.
const PROPERTIES: [PropertyId; 43] = {
    use PropertyId::*;
    [
        Background,
        BorderColor,
        BorderWidth,
        CornerRadius,
        Opacity,
        Transform,
        Shadow,
        Color,
        Filter,
        AccentColor,
        Width,
        Height,
        MinWidth,
        MaxWidth,
        MinHeight,
        MaxHeight,
        Padding,
        Margin,
        Gap,
        FlexDirection,
        AlignItems,
        JustifyContent,
        AlignSelf,
        FlexGrow,
        FlexShrink,
        FlexWrap,
        FlexBasis,
        Display,
        Overflow,
        Position,
        Top,
        Right,
        Bottom,
        Left,
        FontSize,
        FontFamily,
        FontWeight,
        FontStyle,
        LetterSpacing,
        LineHeight,
        TextAlign,
        TextContent,
        Compound,
    ]
};

fn property(raw: i32) -> Option<PropertyId> {
    usize::try_from(raw)
        .ok()
        .and_then(|i| PROPERTIES.get(i))
        .copied()
}

// ============================================================================
// TEXT MEASURE CONTEXT
// ============================================================================

pub type TextWrite = Box<dyn FnOnce(&mut TextMeasureContext) + Send>;

static PENDING_TEXT: Mutex<Vec<(LayoutNodeId, TextWrite)>> = Mutex::new(Vec::new());

fn record_text(node: LayoutNodeId, write: impl FnOnce(&mut TextMeasureContext) + Send + 'static) {
    PENDING_TEXT
        .lock()
        .unwrap_or_else(|e| e.into_inner())
        .push((node, Box::new(write)));
}

/// Text changes recorded since the last call, oldest first.
pub fn take_pending_text() -> Vec<(LayoutNodeId, TextWrite)> {
    std::mem::take(&mut *PENDING_TEXT.lock().unwrap_or_else(|e| e.into_inner()))
}

// ============================================================================
// BINDING
// ============================================================================

type LayoutWrite<T> = Arc<dyn Fn(&mut Style, T) + Send + Sync>;
type RenderWrite<T> = Arc<dyn Fn(&mut RenderProps, T) + Send + Sync>;

/// Where a property's value goes: into the Taffy style (relayout) or into the
/// node's render props.
enum Write<T> {
    Layout(LayoutWrite<T>),
    Render(RenderWrite<T>),
}

fn layout<T>(f: impl Fn(&mut Style, T) + Send + Sync + 'static) -> Option<Write<T>> {
    Some(Write::Layout(Arc::new(f)))
}

fn render<T>(f: impl Fn(&mut RenderProps, T) + Send + Sync + 'static) -> Option<Write<T>> {
    Some(Write::Render(Arc::new(f)))
}

impl<T: Slot> Write<T> {
    fn queue(&self, node: LayoutNodeId, prop: PropertyId, v: T) {
        match self {
            Write::Layout(w) => {
                let w = Arc::clone(w);
                queue_layout_update_partial(node, prop, prop.side_effects(), move |s| w(s, v));
            }
            Write::Render(w) => {
                let w = Arc::clone(w);
                queue_prop_update_partial(node, prop, prop.side_effects(), move |p| w(p, v));
            }
        }
    }
}

/// # Safety
/// `sig` and `comp` must each be null or a handle of their kind.
unsafe fn bind<T: Slot>(
    node: LayoutNodeId,
    prop: PropertyId,
    kind: i32,
    constant: T,
    sig: *mut c_void,
    comp: *mut c_void,
    write: Write<T>,
) {
    match kind {
        KIND_CONST => write.queue(node, prop, constant),
        KIND_SIGNAL => {
            let Some(state) = (unsafe { handle_ref::<AnySignal>(sig) }).and_then(T::state_view)
            else {
                return;
            };
            match &write {
                Write::Layout(w) => {
                    let w = Arc::clone(w);
                    register_typed_layout(
                        state.signal_id(),
                        node,
                        prop,
                        state.clone(),
                        move |s, v| w(s, v),
                    );
                }
                Write::Render(w) => {
                    let w = Arc::clone(w);
                    register_typed(state.signal_id(), node, prop, state.clone(), move |p, v| {
                        w(p, v)
                    });
                }
            }
            write.queue(node, prop, state.try_get().unwrap_or_default());
        }
        KIND_COMPUTED => {
            let Some(c) = (unsafe { handle_ref::<AnyComputed>(comp) }).and_then(T::computed_view)
            else {
                return;
            };
            match &write {
                Write::Layout(w) => {
                    let w = Arc::clone(w);
                    register_typed_layout_computed(
                        c.derived_id(),
                        node,
                        prop,
                        c.clone(),
                        move |s, v| w(s, v),
                    );
                }
                Write::Render(w) => {
                    let w = Arc::clone(w);
                    register_typed_computed(c.derived_id(), node, prop, c.clone(), move |p, v| {
                        w(p, v)
                    });
                }
            }
            write.queue(node, prop, c.try_get().unwrap_or_default());
        }
        _ => {}
    }
}

// ============================================================================
// F32: lengths, flex factors, opacity, typography metrics
// ============================================================================

/// A length in pixels; NaN is `auto`.
fn dimension(v: f32) -> Dimension {
    if v.is_nan() {
        Dimension::Auto
    } else {
        Dimension::Length(v)
    }
}

fn length_auto(v: f32) -> LengthPercentageAuto {
    if v.is_nan() {
        LengthPercentageAuto::Auto
    } else {
        LengthPercentageAuto::Length(v)
    }
}

/// ashui's own number properties, numbered after Blinc's: one side of a
/// box's padding, margin or gap, or a size as a fraction of the parent's.
/// Each is updated under the Blinc property it is part of.
const SIDES_BASE: i32 = 43;

fn side_write(raw: i32) -> Option<(PropertyId, Write<f32>)> {
    use PropertyId as P;
    let pad = |v: f32| LengthPercentage::Length(v);
    Some(match raw - SIDES_BASE {
        0 => (P::Padding, layout(move |s, v| s.padding.top = pad(v))?),
        1 => (P::Padding, layout(move |s, v| s.padding.right = pad(v))?),
        2 => (P::Padding, layout(move |s, v| s.padding.bottom = pad(v))?),
        3 => (P::Padding, layout(move |s, v| s.padding.left = pad(v))?),
        4 => (P::Margin, layout(|s, v| s.margin.top = length_auto(v))?),
        5 => (P::Margin, layout(|s, v| s.margin.right = length_auto(v))?),
        6 => (P::Margin, layout(|s, v| s.margin.bottom = length_auto(v))?),
        7 => (P::Margin, layout(|s, v| s.margin.left = length_auto(v))?),
        // Taffy's gap.width is the gap between columns, gap.height between rows.
        8 => (P::Gap, layout(move |s, v| s.gap.width = pad(v))?),
        9 => (P::Gap, layout(move |s, v| s.gap.height = pad(v))?),
        10 => (
            P::Width,
            layout(|s, v| s.size.width = Dimension::Percent(v))?,
        ),
        11 => (
            P::Height,
            layout(|s, v| s.size.height = Dimension::Percent(v))?,
        ),
        12 => (
            P::MinWidth,
            layout(|s, v| s.min_size.width = Dimension::Percent(v))?,
        ),
        13 => (
            P::MaxWidth,
            layout(|s, v| s.max_size.width = Dimension::Percent(v))?,
        ),
        14 => (
            P::MinHeight,
            layout(|s, v| s.min_size.height = Dimension::Percent(v))?,
        ),
        15 => (
            P::MaxHeight,
            layout(|s, v| s.max_size.height = Dimension::Percent(v))?,
        ),
        16 => (
            P::FlexBasis,
            layout(|s, v| s.flex_basis = Dimension::Percent(v))?,
        ),
        _ => return None,
    })
}

fn f32_write(node: LayoutNodeId, prop: PropertyId) -> Option<Write<f32>> {
    use PropertyId as P;
    match prop {
        P::Width => layout(|s, v| s.size.width = dimension(v)),
        P::Height => layout(|s, v| s.size.height = dimension(v)),
        P::MinWidth => layout(|s, v| s.min_size.width = dimension(v)),
        P::MaxWidth => layout(|s, v| s.max_size.width = dimension(v)),
        P::MinHeight => layout(|s, v| s.min_size.height = dimension(v)),
        P::MaxHeight => layout(|s, v| s.max_size.height = dimension(v)),
        P::FlexBasis => layout(|s, v| s.flex_basis = dimension(v)),
        P::FlexGrow => layout(|s, v| s.flex_grow = v),
        P::FlexShrink => layout(|s, v| s.flex_shrink = v),
        P::Padding => layout(|s, v| {
            let l = LengthPercentage::Length(v);
            s.padding = Rect {
                left: l,
                right: l,
                top: l,
                bottom: l,
            };
        }),
        P::Margin => layout(|s, v| {
            let l = length_auto(v);
            s.margin = Rect {
                left: l,
                right: l,
                top: l,
                bottom: l,
            };
        }),
        P::Gap => layout(|s, v| {
            let l = LengthPercentage::Length(v);
            s.gap = Size {
                width: l,
                height: l,
            };
        }),
        P::Top => layout(|s, v| s.inset.top = length_auto(v)),
        P::Right => layout(|s, v| s.inset.right = length_auto(v)),
        P::Bottom => layout(|s, v| s.inset.bottom = length_auto(v)),
        P::Left => layout(|s, v| s.inset.left = length_auto(v)),
        P::Opacity => render(|p, v| p.opacity = v),
        P::BorderWidth => render(|p, v| p.border_width = v),
        P::FontSize => render(move |p, v| {
            p.font_size = Some(v);
            record_text(node, move |c| c.font_size = v);
        }),
        P::LetterSpacing => render(|p, v| p.letter_spacing = Some(v)),
        P::LineHeight => render(move |p, v| {
            p.line_height = Some(v);
            record_text(node, move |c| c.line_height = v);
        }),
        _ => None,
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn hl_blinc_apply_f32(
    node: u64,
    prop: i32,
    kind: i32,
    constant: f32,
    sig: *mut c_void,
    comp: *mut c_void,
) {
    let node = LayoutNodeId::from_raw(node);
    if let Some((prop, write)) = side_write(prop) {
        unsafe { bind(node, prop, kind, constant, sig, comp, write) };
        return;
    }
    let Some(prop) = property(prop) else { return };
    let Some(write) = f32_write(node, prop) else {
        return;
    };
    unsafe { bind(node, prop, kind, constant, sig, comp, write) };
}
define_prim!(
    hlp_blinc_apply_f32,
    hl_blinc_apply_f32,
    "PliifXblinc_signal_Xblinc_computed__v"
);

// ============================================================================
// I32: layout and text enums
// ============================================================================

fn display(v: i32) -> Display {
    match v {
        0 => Display::Block,
        2 => Display::Grid,
        3 => Display::None,
        _ => Display::Flex,
    }
}

fn flex_direction(v: i32) -> FlexDirection {
    match v {
        1 => FlexDirection::Column,
        2 => FlexDirection::RowReverse,
        3 => FlexDirection::ColumnReverse,
        _ => FlexDirection::Row,
    }
}

fn flex_wrap(v: i32) -> FlexWrap {
    match v {
        1 => FlexWrap::Wrap,
        2 => FlexWrap::WrapReverse,
        _ => FlexWrap::NoWrap,
    }
}

/// `None` is `auto`.
fn align_items(v: i32) -> Option<AlignItems> {
    Some(match v {
        0 => AlignItems::Start,
        1 => AlignItems::End,
        2 => AlignItems::FlexStart,
        3 => AlignItems::FlexEnd,
        4 => AlignItems::Center,
        5 => AlignItems::Baseline,
        6 => AlignItems::Stretch,
        _ => return None,
    })
}

/// `None` is `normal`.
fn justify_content(v: i32) -> Option<JustifyContent> {
    Some(match v {
        0 => JustifyContent::Start,
        1 => JustifyContent::End,
        2 => JustifyContent::FlexStart,
        3 => JustifyContent::FlexEnd,
        4 => JustifyContent::Center,
        5 => JustifyContent::Stretch,
        6 => JustifyContent::SpaceBetween,
        7 => JustifyContent::SpaceEvenly,
        8 => JustifyContent::SpaceAround,
        _ => return None,
    })
}

fn position(v: i32) -> Position {
    match v {
        1 => Position::Absolute,
        _ => Position::Relative,
    }
}

fn overflow(v: i32) -> Overflow {
    match v {
        1 => Overflow::Clip,
        2 => Overflow::Hidden,
        3 => Overflow::Scroll,
        _ => Overflow::Visible,
    }
}

/// A CSS numeric weight, to the nearest named one.
fn font_weight(v: i32) -> FontWeight {
    match v {
        ..=149 => FontWeight::Thin,
        150..=249 => FontWeight::ExtraLight,
        250..=349 => FontWeight::Light,
        350..=449 => FontWeight::Normal,
        450..=549 => FontWeight::Medium,
        550..=649 => FontWeight::SemiBold,
        650..=749 => FontWeight::Bold,
        750..=849 => FontWeight::ExtraBold,
        _ => FontWeight::Black,
    }
}

fn font_style(v: i32) -> FontStyle {
    match v {
        1 => FontStyle::Italic,
        _ => FontStyle::Normal,
    }
}

fn text_align(v: i32) -> TextAlign {
    match v {
        1 => TextAlign::Center,
        2 => TextAlign::Right,
        _ => TextAlign::Left,
    }
}

fn i32_write(node: LayoutNodeId, prop: PropertyId) -> Option<Write<i32>> {
    use PropertyId as P;
    match prop {
        P::Display => layout(|s, v| s.display = display(v)),
        P::FlexDirection => layout(|s, v| s.flex_direction = flex_direction(v)),
        P::FlexWrap => layout(|s, v| s.flex_wrap = flex_wrap(v)),
        P::AlignItems => layout(|s, v| s.align_items = align_items(v)),
        P::AlignSelf => layout(|s, v| s.align_self = align_items(v)),
        P::JustifyContent => layout(|s, v| s.justify_content = justify_content(v)),
        P::Position => layout(|s, v| s.position = position(v)),
        P::Overflow => layout(|s, v| {
            let o = overflow(v);
            s.overflow = Point { x: o, y: o };
        }),
        P::FontWeight => render(move |p, v| {
            p.font_weight = Some(font_weight(v));
            record_text(node, move |c| c.font_weight = v.clamp(1, 1000) as u16);
        }),
        P::FontStyle => render(move |p, v| {
            p.font_style = Some(font_style(v));
            record_text(node, move |c| c.italic = v == 1);
        }),
        P::TextAlign => render(|p, v| p.text_align = Some(text_align(v))),
        _ => None,
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn hl_blinc_apply_i32(
    node: u64,
    prop: i32,
    kind: i32,
    constant: i32,
    sig: *mut c_void,
    comp: *mut c_void,
) {
    let node = LayoutNodeId::from_raw(node);
    let Some(prop) = property(prop) else { return };
    let Some(write) = i32_write(node, prop) else {
        return;
    };
    unsafe { bind(node, prop, kind, constant, sig, comp, write) };
}
define_prim!(
    hlp_blinc_apply_i32,
    hl_blinc_apply_i32,
    "PliiiXblinc_signal_Xblinc_computed__v"
);

// ============================================================================
// VALUES: brushes, colors, radii, transforms, shadows
// ============================================================================

/// A value of the wrong variant for the property is ignored.
fn value_write(prop: PropertyId) -> Option<Write<Value>> {
    use PropertyId as P;
    match prop {
        P::Background => render(|p, v| match v {
            Value::Brush(b) => p.background = Some(b),
            Value::Color(c) => p.background = Some(c.into()),
            _ => {}
        }),
        P::BorderColor => render(|p, v| {
            if let Value::Color(c) = v {
                p.border_color = Some(c);
            }
        }),
        P::Color => render(|p, v| {
            if let Value::Color(c) = v {
                p.text_color = Some(c.to_array());
            }
        }),
        P::AccentColor => render(|p, v| {
            if let Value::Color(c) = v {
                p.outline_color = Some(c);
            }
        }),
        // The radius and the corner shape share this property.
        P::CornerRadius => render(|p, v| match v {
            Value::Radius(r) => {
                p.border_radius = r;
                p.border_radius_explicit = true;
            }
            Value::CornerShape(n, locked) => {
                p.corner_shape = CornerShape::new(n[0], n[1], n[2], n[3]);
                p.corner_shape_locked = locked;
            }
            _ => {}
        }),
        P::Transform => render(|p, v| {
            if let Value::Transform(t) = v {
                p.transform = Some(t);
            }
        }),
        P::Shadow => render(|p, v| {
            if let Value::Shadow(s) = v {
                p.shadow = s;
            }
        }),
        _ => None,
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn hl_blinc_apply_value(
    node: u64,
    prop: i32,
    kind: i32,
    constant: *mut c_void,
    sig: *mut c_void,
    comp: *mut c_void,
) {
    let Some(prop) = property(prop) else { return };
    let Some(write) = value_write(prop) else {
        return;
    };
    let constant = unsafe { handle_ref::<Value>(constant) }
        .cloned()
        .unwrap_or_default();
    unsafe {
        bind(
            LayoutNodeId::from_raw(node),
            prop,
            kind,
            constant,
            sig,
            comp,
            write,
        )
    };
}
define_prim!(
    hlp_blinc_apply_value,
    hl_blinc_apply_value,
    "PliiXblinc_value_Xblinc_signal_Xblinc_computed__v"
);

// ============================================================================
// STRINGS
// ============================================================================

/// `TextContent` and `FontFamily`. Both live only in a text node's measure
/// context: Blinc's `RenderProps` has neither field.
fn string_write(node: LayoutNodeId, prop: PropertyId) -> Option<Write<Option<String>>> {
    use PropertyId as P;
    match prop {
        P::TextContent => render(move |_, v: Option<String>| {
            record_text(node, move |c| c.content = v.unwrap_or_default())
        }),
        P::FontFamily => render(move |_, v: Option<String>| {
            record_text(node, move |c| c.font_name = v.filter(|v| !v.is_empty()))
        }),
        _ => None,
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn hl_blinc_apply_string(
    node: u64,
    prop: i32,
    kind: i32,
    constant: *const vbyte,
    sig: *mut c_void,
    comp: *mut c_void,
) {
    let node = LayoutNodeId::from_raw(node);
    let Some(prop) = property(prop) else { return };
    let Some(write) = string_write(node, prop) else {
        return;
    };
    let constant = unsafe { opt_string_from(constant) };
    unsafe { bind(node, prop, kind, constant, sig, comp, write) };
}
define_prim!(
    hlp_blinc_apply_string,
    hl_blinc_apply_string,
    "PliiBXblinc_signal_Xblinc_computed__v"
);
