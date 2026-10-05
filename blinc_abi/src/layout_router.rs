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
use blinc_layout::element::{BorderSide, RenderProps};
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

/// The identity of each backdrop colour filter: brightness, contrast,
/// grayscale, hue-rotate, invert, saturate, sepia.
pub const BACKDROP_IDENTITY: [f32; 7] = [1.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0];

/// A backdrop colour filter's change: the node, which filter (an index into `BACKDROP_IDENTITY`), its value.
static PENDING_BACKDROP: Mutex<Vec<(LayoutNodeId, usize, f32)>> = Mutex::new(Vec::new());

fn record_backdrop(node: LayoutNodeId, filter: usize, value: f32) {
    PENDING_BACKDROP.lock().unwrap_or_else(|e| e.into_inner()).push((node, filter, value));
}

/// Backdrop filter changes recorded since the last call, oldest first. Blinc's
/// render props have no backdrop filter, so ashui keeps them beside the tree.
pub fn take_pending_backdrop() -> Vec<(LayoutNodeId, usize, f32)> {
    std::mem::take(&mut *PENDING_BACKDROP.lock().unwrap_or_else(|e| e.into_inner()))
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
        Dimension::auto()
    } else {
        Dimension::length(v)
    }
}

fn length_auto(v: f32) -> LengthPercentageAuto {
    if v.is_nan() {
        LengthPercentageAuto::auto()
    } else {
        LengthPercentageAuto::length(v)
    }
}

/// ashui's own number properties, numbered after Blinc's: one side of a
/// box's padding, margin, gap or border, a size as a fraction of the
/// parent's, an outline's width or offset, one side's overflow fade, or a
/// colour filter's amount. Each is updated under the
/// Blinc property it is part of.
const SIDES_BASE: i32 = 43;

fn side_write(node: LayoutNodeId, raw: i32) -> Option<(PropertyId, Write<f32>)> {
    use PropertyId as P;
    let pad = |v: f32| LengthPercentage::length(v);
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
            layout(|s, v| s.size.width = Dimension::percent(v))?,
        ),
        11 => (
            P::Height,
            layout(|s, v| s.size.height = Dimension::percent(v))?,
        ),
        12 => (
            P::MinWidth,
            layout(|s, v| s.min_size.width = LengthPercentageAuto::percent(v))?,
        ),
        13 => (
            P::MaxWidth,
            layout(|s, v| s.max_size.width = LengthPercentageAuto::percent(v))?,
        ),
        14 => (
            P::MinHeight,
            layout(|s, v| s.min_size.height = LengthPercentageAuto::percent(v))?,
        ),
        15 => (
            P::MaxHeight,
            layout(|s, v| s.max_size.height = LengthPercentageAuto::percent(v))?,
        ),
        16 => (
            P::FlexBasis,
            layout(|s, v| s.flex_basis = Dimension::percent(v))?,
        ),
        // A side's width over the border's.
        17 => (P::BorderWidth, render(|p, v| side(&mut p.border_sides.top).width = v)?),
        18 => (P::BorderWidth, render(|p, v| side(&mut p.border_sides.right).width = v)?),
        19 => (P::BorderWidth, render(|p, v| side(&mut p.border_sides.bottom).width = v)?),
        20 => (P::BorderWidth, render(|p, v| side(&mut p.border_sides.left).width = v)?),
        21 => (P::BorderWidth, render(|p, v| p.outline_width = v)?),
        22 => (P::BorderWidth, render(|p, v| p.outline_offset = v)?),
        // How far in from a side a clipping box fades what it clips.
        28 => (P::Opacity, render(|p, v| p.overflow_fade.top = v)?),
        29 => (P::Opacity, render(|p, v| p.overflow_fade.right = v)?),
        30 => (P::Opacity, render(|p, v| p.overflow_fade.bottom = v)?),
        31 => (P::Opacity, render(|p, v| p.overflow_fade.left = v)?),
        // CSS's colour filters, each over the identity: 1 for brightness, contrast and saturate, 0 for the rest.
        33 => (P::Filter, render(|p, v| filter(p).brightness = v)?),
        34 => (P::Filter, render(|p, v| filter(p).contrast = v)?),
        35 => (P::Filter, render(|p, v| filter(p).grayscale = v)?),
        36 => (P::Filter, render(|p, v| filter(p).hue_rotate = v)?),
        37 => (P::Filter, render(|p, v| filter(p).invert = v)?),
        38 => (P::Filter, render(|p, v| filter(p).saturate = v)?),
        39 => (P::Filter, render(|p, v| filter(p).sepia = v)?),
        40 => (P::Filter, render(|p, v| filter(p).blur = v)?),
        // Width over height; NaN or none positive is no ratio.
        47 => (P::Width, layout(|s, v: f32| s.aspect_ratio = if v.is_finite() && v > 0.0 { Some(v) } else { None })?),
        // Whether text breaks lines at its width, as CSS's white-space: 0 keeps it to one line.
        48 => (P::TextAlign, render(move |_, v: f32| record_text(node, move |c| c.wrap = v != 0.0))?),
        // The backdrop's colour filters, in BACKDROP_IDENTITY's order.
        49..=55 => {
            let filter = (raw - SIDES_BASE - 49) as usize;
            (P::Background, render(move |_, v: f32| record_backdrop(node, filter, v))?)
        }
        _ => return None,
    })
}

/// A border side, made with its width and colour unset, so a side can set
/// one and take the border's other: a negative width and a NaN red, which
/// `display_list` reads as the border's.
fn side(slot: &mut Option<BorderSide>) -> &mut BorderSide {
    slot.get_or_insert(BorderSide {
        width: -1.0,
        color: blinc_core::Color {
            r: f32::NAN,
            g: 0.0,
            b: 0.0,
            a: 0.0,
        },
    })
}

fn filter(p: &mut RenderProps) -> &mut blinc_layout::element_style::CssFilter {
    p.filter.get_or_insert_with(Default::default)
}

/// ashui's own value properties, numbered after its number ones: the
/// outline's colour, each border side's, and the clip path.
fn own_value_write(raw: i32) -> Option<(PropertyId, Write<Value>)> {
    fn color(f: fn(&mut RenderProps, blinc_core::Color)) -> Option<Write<Value>> {
        render(move |p, v| {
            if let Value::Color(c) = v {
                f(p, c);
            }
        })
    }
    Some(match raw {
        66 => (PropertyId::AccentColor, color(|p, c| p.outline_color = Some(c))?),
        67 => (PropertyId::BorderColor, color(|p, c| side(&mut p.border_sides.top).color = c)?),
        68 => (PropertyId::BorderColor, color(|p, c| side(&mut p.border_sides.right).color = c)?),
        69 => (PropertyId::BorderColor, color(|p, c| side(&mut p.border_sides.bottom).color = c)?),
        70 => (PropertyId::BorderColor, color(|p, c| side(&mut p.border_sides.left).color = c)?),
        // CSS's mask-image: a gradient whose alpha the element and what it holds are drawn through.
        89 => (
            PropertyId::Filter,
            render(|p, v| {
                p.mask_image = match v {
                    Value::Brush(blinc_core::Brush::Gradient(g)) => Some(blinc_core::MaskImage::Gradient(g)),
                    _ => None,
                };
            })?,
        ),
        84 => (
            PropertyId::Filter,
            render(|p, v| {
                filter(p).drop_shadow = match v {
                    Value::Shadow(outer, _) => outer.first().copied(),
                    _ => None,
                };
            })?,
        ),
        75 => (
            PropertyId::Transform,
            render(|p, v| {
                p.clip_path = match v {
                    Value::ClipPath(c) => Some(c),
                    _ => None,
                };
            })?,
        ),
        _ => return None,
    })
}

fn f32_write(node: LayoutNodeId, prop: PropertyId) -> Option<Write<f32>> {
    use PropertyId as P;
    match prop {
        P::Width => layout(|s, v| s.size.width = dimension(v)),
        P::Height => layout(|s, v| s.size.height = dimension(v)),
        P::MinWidth => layout(|s, v| s.min_size.width = length_auto(v)),
        P::MaxWidth => layout(|s, v| s.max_size.width = length_auto(v)),
        P::MinHeight => layout(|s, v| s.min_size.height = length_auto(v)),
        P::MaxHeight => layout(|s, v| s.max_size.height = length_auto(v)),
        P::FlexBasis => layout(|s, v| s.flex_basis = dimension(v)),
        P::FlexGrow => layout(|s, v| s.flex_grow = v),
        P::FlexShrink => layout(|s, v| s.flex_shrink = v),
        P::Padding => layout(|s, v| {
            let l = LengthPercentage::length(v);
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
            let l = LengthPercentage::length(v);
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
        P::LetterSpacing => render(move |p, v| {
            p.letter_spacing = Some(v);
            record_text(node, move |c| c.letter_spacing = v);
        }),
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
    if let Some((prop, write)) = side_write(node, prop) {
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
        0 => AlignItems::START,
        1 => AlignItems::END,
        2 => AlignItems::FLEX_START,
        3 => AlignItems::FLEX_END,
        4 => AlignItems::CENTER,
        5 => AlignItems::BASELINE,
        6 => AlignItems::STRETCH,
        _ => return None,
    })
}

/// `None` is `normal`.
fn justify_content(v: i32) -> Option<JustifyContent> {
    Some(match v {
        0 => JustifyContent::START,
        1 => JustifyContent::END,
        2 => JustifyContent::FLEX_START,
        3 => JustifyContent::FLEX_END,
        4 => JustifyContent::CENTER,
        5 => JustifyContent::STRETCH,
        6 => JustifyContent::SPACE_BETWEEN,
        7 => JustifyContent::SPACE_EVENLY,
        8 => JustifyContent::SPACE_AROUND,
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
            if let Value::Shadow(outer, inner) = v {
                p.shadow = outer;
                p.inner_shadow = inner;
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
    let (prop, write) = if let Some(own) = own_value_write(prop) {
        own
    } else {
        let Some(prop) = property(prop) else { return };
        let Some(write) = value_write(prop) else {
            return;
        };
        (prop, write)
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
            let (name, generic) = v.as_deref().map(crate::text::resolve_family).unwrap_or_default();
            record_text(node, move |c| {
                c.font_name = name;
                c.generic_font = generic;
            })
        }),
        _ => None,
    }
}

/// ashui's grid properties, written as CSS text: `GridTemplateColumns`
/// (85), `GridTemplateRows` (86), `GridColumn` (87) and `GridRow` (88).
/// Text that does not parse puts the default back.
fn own_string_write(raw: i32) -> Option<(PropertyId, Write<Option<String>>)> {
    // The defaults are read inside each writer: a taffy style value is not Send, so none is captured.
    let write: Write<Option<String>> = match raw {
        85 => layout(|s, v: Option<String>| s.grid_template_columns = v.as_deref().and_then(crate::grid::template).unwrap_or_default())?,
        86 => layout(|s, v: Option<String>| s.grid_template_rows = v.as_deref().and_then(crate::grid::template).unwrap_or_default())?,
        87 => layout(|s, v: Option<String>| {
            s.grid_column = v.as_deref().and_then(crate::grid::line_pair).unwrap_or_else(|| <Style>::DEFAULT.grid_column.clone())
        })?,
        88 => layout(|s, v: Option<String>| {
            s.grid_row = v.as_deref().and_then(crate::grid::line_pair).unwrap_or_else(|| <Style>::DEFAULT.grid_row.clone())
        })?,
        _ => return None,
    };
    // Changing tracks or placement relayouts, as Display does.
    Some((PropertyId::Display, write))
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
    let (prop, write) = if let Some(own) = own_string_write(prop) {
        own
    } else {
        let Some(prop) = property(prop) else { return };
        let Some(write) = string_write(node, prop) else {
            return;
        };
        (prop, write)
    };
    let constant = unsafe { opt_string_from(constant) };
    unsafe { bind(node, prop, kind, constant, sig, comp, write) };
}
define_prim!(
    hlp_blinc_apply_string,
    hl_blinc_apply_string,
    "PliiBXblinc_signal_Xblinc_computed__v"
);

// ============================================================================
// UNSET: a property back to what a new node has
// ============================================================================

/// Corner shapes share CornerRadius's property; this id resets the shape alone.
const CORNER_SHAPE: i32 = 1003;

/// Puts property `raw` (an ashui `PropertyId`, or `CORNER_SHAPE`) of `node`
/// back to its value on a new node: taffy's default style, Blinc's default
/// render props, and for text the measurer's defaults `Text` starts from.
/// A per-side or percentage id resets the field it writes, so `Width` and
/// `WidthPercent` reset the same one. A binding to a signal or computed is
/// not dropped; unset only what was set to a constant.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn hl_blinc_unset(node: u64, raw: i32) {
    let node = LayoutNodeId::from_raw(node);
    let lay = |prop: PropertyId, f: Box<dyn Fn(&mut Style) + Send + Sync>| {
        queue_layout_update_partial(node, prop, prop.side_effects(), move |s| f(s))
    };
    let ren = |prop: PropertyId, f: Box<dyn Fn(&mut RenderProps) + Send + Sync>| {
        queue_prop_update_partial(node, prop, prop.side_effects(), move |p| f(p))
    };
    use PropertyId as P;
    match raw {
        0 => ren(P::Background, Box::new(|p| p.background = None)),
        1 => ren(P::BorderColor, Box::new(|p| p.border_color = None)),
        2 => ren(P::BorderWidth, Box::new(|p| p.border_width = RenderProps::default().border_width)),
        3 => ren(P::CornerRadius, Box::new(|p| {
            p.border_radius = Default::default();
            p.border_radius_explicit = false;
        })),
        CORNER_SHAPE => ren(P::CornerRadius, Box::new(|p| {
            let d = RenderProps::default();
            p.corner_shape = d.corner_shape;
            p.corner_shape_locked = d.corner_shape_locked;
        })),
        4 => ren(P::Opacity, Box::new(|p| p.opacity = 1.0)),
        5 => ren(P::Transform, Box::new(|p| p.transform = None)),
        6 => ren(P::Shadow, Box::new(|p| {
            p.shadow = Default::default();
            p.inner_shadow = Default::default();
        })),
        7 => ren(P::Color, Box::new(|p| p.text_color = None)),
        8 => ren(P::Filter, Box::new(|p| p.filter = None)),
        9 | 66 => ren(P::AccentColor, Box::new(|p| p.outline_color = None)),
        10 | 53 => lay(P::Width, Box::new(move |s| s.size.width = <Style>::DEFAULT.size.width)),
        11 | 54 => lay(P::Height, Box::new(move |s| s.size.height = <Style>::DEFAULT.size.height)),
        12 | 55 => lay(P::MinWidth, Box::new(move |s| s.min_size.width = <Style>::DEFAULT.min_size.width)),
        13 | 56 => lay(P::MaxWidth, Box::new(move |s| s.max_size.width = <Style>::DEFAULT.max_size.width)),
        14 | 57 => lay(P::MinHeight, Box::new(move |s| s.min_size.height = <Style>::DEFAULT.min_size.height)),
        15 | 58 => lay(P::MaxHeight, Box::new(move |s| s.max_size.height = <Style>::DEFAULT.max_size.height)),
        16 => lay(P::Padding, Box::new(move |s| s.padding = <Style>::DEFAULT.padding)),
        17 => lay(P::Margin, Box::new(move |s| s.margin = <Style>::DEFAULT.margin)),
        18 => lay(P::Gap, Box::new(move |s| s.gap = <Style>::DEFAULT.gap)),
        19 => lay(P::FlexDirection, Box::new(move |s| s.flex_direction = <Style>::DEFAULT.flex_direction)),
        20 => lay(P::AlignItems, Box::new(move |s| s.align_items = <Style>::DEFAULT.align_items)),
        21 => lay(P::JustifyContent, Box::new(move |s| s.justify_content = <Style>::DEFAULT.justify_content)),
        22 => lay(P::AlignSelf, Box::new(move |s| s.align_self = <Style>::DEFAULT.align_self)),
        23 => lay(P::FlexGrow, Box::new(move |s| s.flex_grow = <Style>::DEFAULT.flex_grow)),
        24 => lay(P::FlexShrink, Box::new(move |s| s.flex_shrink = <Style>::DEFAULT.flex_shrink)),
        25 => lay(P::FlexWrap, Box::new(move |s| s.flex_wrap = <Style>::DEFAULT.flex_wrap)),
        26 | 59 => lay(P::FlexBasis, Box::new(move |s| s.flex_basis = <Style>::DEFAULT.flex_basis)),
        27 => lay(P::Display, Box::new(move |s| s.display = <Style>::DEFAULT.display)),
        28 => lay(P::Overflow, Box::new(move |s| s.overflow = <Style>::DEFAULT.overflow)),
        29 => lay(P::Position, Box::new(move |s| s.position = <Style>::DEFAULT.position)),
        30 => lay(P::Top, Box::new(move |s| s.inset.top = <Style>::DEFAULT.inset.top)),
        31 => lay(P::Right, Box::new(move |s| s.inset.right = <Style>::DEFAULT.inset.right)),
        32 => lay(P::Bottom, Box::new(move |s| s.inset.bottom = <Style>::DEFAULT.inset.bottom)),
        33 => lay(P::Left, Box::new(move |s| s.inset.left = <Style>::DEFAULT.inset.left)),
        34 => ren(P::FontSize, Box::new(move |p| {
            p.font_size = None;
            record_text(node, |c| c.font_size = 16.0);
        })),
        35 => ren(P::FontFamily, Box::new(move |_| {
            record_text(node, |c| {
                c.font_name = None;
                c.generic_font = Default::default();
            })
        })),
        36 => ren(P::FontWeight, Box::new(move |p| {
            p.font_weight = None;
            record_text(node, |c| c.font_weight = 400);
        })),
        37 => ren(P::FontStyle, Box::new(move |p| {
            p.font_style = None;
            record_text(node, |c| c.italic = false);
        })),
        38 => ren(P::LetterSpacing, Box::new(move |p| {
            p.letter_spacing = None;
            record_text(node, |c| c.letter_spacing = 0.0);
        })),
        39 => ren(P::LineHeight, Box::new(move |p| {
            p.line_height = None;
            record_text(node, |c| c.line_height = 1.2);
        })),
        40 => ren(P::TextAlign, Box::new(|p| p.text_align = None)),
        43 => lay(P::Padding, Box::new(move |s| s.padding.top = LengthPercentage::length(0.0))),
        44 => lay(P::Padding, Box::new(move |s| s.padding.right = LengthPercentage::length(0.0))),
        45 => lay(P::Padding, Box::new(move |s| s.padding.bottom = LengthPercentage::length(0.0))),
        46 => lay(P::Padding, Box::new(move |s| s.padding.left = LengthPercentage::length(0.0))),
        47 => lay(P::Margin, Box::new(move |s| s.margin.top = <Style>::DEFAULT.margin.top)),
        48 => lay(P::Margin, Box::new(move |s| s.margin.right = <Style>::DEFAULT.margin.right)),
        49 => lay(P::Margin, Box::new(move |s| s.margin.bottom = <Style>::DEFAULT.margin.bottom)),
        50 => lay(P::Margin, Box::new(move |s| s.margin.left = <Style>::DEFAULT.margin.left)),
        51 => lay(P::Gap, Box::new(move |s| s.gap.width = LengthPercentage::length(0.0))),
        52 => lay(P::Gap, Box::new(move |s| s.gap.height = LengthPercentage::length(0.0))),
        60 => ren(P::BorderWidth, Box::new(|p| side(&mut p.border_sides.top).width = -1.0)),
        61 => ren(P::BorderWidth, Box::new(|p| side(&mut p.border_sides.right).width = -1.0)),
        62 => ren(P::BorderWidth, Box::new(|p| side(&mut p.border_sides.bottom).width = -1.0)),
        63 => ren(P::BorderWidth, Box::new(|p| side(&mut p.border_sides.left).width = -1.0)),
        64 => ren(P::BorderWidth, Box::new(|p| p.outline_width = RenderProps::default().outline_width)),
        65 => ren(P::BorderWidth, Box::new(|p| p.outline_offset = RenderProps::default().outline_offset)),
        67..=70 => {
            let unset = blinc_core::Color { r: f32::NAN, g: 0.0, b: 0.0, a: 0.0 };
            ren(P::BorderColor, Box::new(move |p| {
                let s = &mut p.border_sides;
                let slot = match raw {
                    67 => &mut s.top,
                    68 => &mut s.right,
                    69 => &mut s.bottom,
                    _ => &mut s.left,
                };
                side(slot).color = unset;
            }))
        }
        71 => ren(P::Opacity, Box::new(|p| p.overflow_fade.top = 0.0)),
        72 => ren(P::Opacity, Box::new(|p| p.overflow_fade.right = 0.0)),
        73 => ren(P::Opacity, Box::new(|p| p.overflow_fade.bottom = 0.0)),
        74 => ren(P::Opacity, Box::new(|p| p.overflow_fade.left = 0.0)),
        75 => ren(P::Transform, Box::new(|p| p.clip_path = None)),
        // Each colour filter back to its identity.
        76 => ren(P::Filter, Box::new(|p| filter(p).brightness = 1.0)),
        77 => ren(P::Filter, Box::new(|p| filter(p).contrast = 1.0)),
        78 => ren(P::Filter, Box::new(|p| filter(p).grayscale = 0.0)),
        79 => ren(P::Filter, Box::new(|p| filter(p).hue_rotate = 0.0)),
        80 => ren(P::Filter, Box::new(|p| filter(p).invert = 0.0)),
        81 => ren(P::Filter, Box::new(|p| filter(p).saturate = 1.0)),
        82 => ren(P::Filter, Box::new(|p| filter(p).sepia = 0.0)),
        83 => ren(P::Filter, Box::new(|p| filter(p).blur = 0.0)),
        84 => ren(P::Filter, Box::new(|p| filter(p).drop_shadow = None)),
        85 => lay(P::Display, Box::new(move |s| s.grid_template_columns = Vec::new())),
        86 => lay(P::Display, Box::new(move |s| s.grid_template_rows = Vec::new())),
        87 => lay(P::Display, Box::new(move |s| s.grid_column = Line { start: GridPlacement::Auto, end: GridPlacement::Auto })),
        88 => lay(P::Display, Box::new(move |s| s.grid_row = Line { start: GridPlacement::Auto, end: GridPlacement::Auto })),
        89 => ren(P::Filter, Box::new(|p| p.mask_image = None)),
        90 => lay(P::Width, Box::new(|s| s.aspect_ratio = None)),
        91 => ren(P::TextAlign, Box::new(move |_| record_text(node, |c| c.wrap = true))),
        92..=98 => {
            let filter = (raw - 92) as usize;
            ren(P::Background, Box::new(move |_| record_backdrop(node, filter, BACKDROP_IDENTITY[filter])))
        }
        _ => {}
    }
}
define_prim!(hlp_blinc_unset, hl_blinc_unset, "li_v");
