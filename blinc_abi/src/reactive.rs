//! Signals and computeds on Blinc's global reactive graph, as Haxe handles.
//!
//! A computed is a Haxe `Void->Void` closure. It reads signals through the
//! getters below, which go through `Signal::get`: inside a computation that
//! takes Blinc's in-flight path, so the read is recorded as a dependency and
//! never re-locks the graph the computation runs under. The closure hands its
//! result back through `blinc_return_*` rather than as a return value, so no
//! value has to be boxed through `hl_dyn_call`.

use crate::hl::{Rooted, call_void, handle_ref, into_handle, opt_string_from, string_to_hl};
use crate::types::Value;
use blinc_core::reactive::{
    Computed, DerivedId, Effect, SignalId, State, computed, dispose_derived, dispose_signal,
    effect, global_dirty_flag, global_graph, signal,
};
use blinc_layout::binding::with_registry;
use hl_abi::{define_prim, vbyte};
use std::any::Any;
use std::cell::RefCell;
use std::ffi::c_void;
use std::sync::atomic::Ordering;
use std::sync::{Arc, Mutex};

pub enum AnySignal {
    I32(State<i32>),
    F32(State<f32>),
    F64(State<f64>),
    Bool(State<bool>),
    Str(State<Option<String>>),
    Value(State<Value>),
}

pub enum AnyComputed {
    I32(Computed<i32>),
    F32(Computed<f32>),
    F64(Computed<f64>),
    Bool(Computed<bool>),
    Str(Computed<Option<String>>),
    Value(Computed<Value>),
}

// ============================================================================
// RELEASE
// ============================================================================
// A handle's finalizer only queues its id: stock HashLink runs finalizers
// inside a collection, where a computation may already hold Blinc's graph
// lock. `collect_released` removes them later, at a flush.

static RELEASED_SIGNALS: Mutex<Vec<SignalId>> = Mutex::new(Vec::new());
static RELEASED_DERIVEDS: Mutex<Vec<DerivedId>> = Mutex::new(Vec::new());
static RELEASED_EFFECTS: Mutex<Vec<Effect>> = Mutex::new(Vec::new());

fn drain_queue<T>(queue: &Mutex<Vec<T>>) -> Vec<T> {
    std::mem::take(&mut *queue.lock().unwrap_or_else(|e| e.into_inner()))
}

impl Drop for AnySignal {
    fn drop(&mut self) {
        let id = match self {
            AnySignal::I32(s) => s.signal_id(),
            AnySignal::F32(s) => s.signal_id(),
            AnySignal::F64(s) => s.signal_id(),
            AnySignal::Bool(s) => s.signal_id(),
            AnySignal::Str(s) => s.signal_id(),
            AnySignal::Value(s) => s.signal_id(),
        };
        RELEASED_SIGNALS
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .push(id);
    }
}

impl AnyComputed {
    fn derived_id(&self) -> DerivedId {
        match self {
            AnyComputed::I32(c) => c.derived_id(),
            AnyComputed::F32(c) => c.derived_id(),
            AnyComputed::F64(c) => c.derived_id(),
            AnyComputed::Bool(c) => c.derived_id(),
            AnyComputed::Str(c) => c.derived_id(),
            AnyComputed::Value(c) => c.derived_id(),
        }
    }

    fn release(&self) {
        RELEASED_DERIVEDS
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .push(self.derived_id());
    }
}

impl Drop for AnyComputed {
    fn drop(&mut self) {
        self.release();
    }
}

/// Remove released signals from Blinc's graph, and released computeds that
/// no node is bound to. Nothing can set a released signal, so its bindings
/// keep their last value; a released computed still follows its signals, so
/// one that is bound waits here until its node is removed.
///
/// Not to be called from a property binding firing: it takes the binding
/// registry's lock.
pub fn collect_released() {
    for id in drain_queue(&RELEASED_SIGNALS) {
        dispose_signal(id);
    }
    let mut bound = Vec::new();
    for id in drain_queue(&RELEASED_DERIVEDS) {
        if with_registry(|r| r.derived_subscriber_count(id)) == 0 {
            dispose_derived(id);
        } else {
            bound.push(id);
        }
    }
    RELEASED_DERIVEDS
        .lock()
        .unwrap_or_else(|e| e.into_inner())
        .extend(bound);
    let effects = drain_queue(&RELEASED_EFFECTS);
    if !effects.is_empty() {
        let graph = global_graph();
        let mut g = graph.lock().unwrap_or_else(|e| e.into_inner());
        for e in effects {
            g.dispose_effect(e);
        }
    }
}

/// A type a signal or computed can hold, and how to find it in a handle.
/// A handle of another type reads as absent rather than being reinterpreted.
pub trait Slot: Clone + Default + Send + Sync + 'static {
    fn state(s: &AnySignal) -> Option<&State<Self>>;
    fn computed(c: &AnyComputed) -> Option<&Computed<Self>>;

    /// What a binding of this type subscribes to: the handle's own state, or
    /// a view of another type that reads as this one.
    fn state_view(s: &AnySignal) -> Option<State<Self>> {
        Self::state(s).cloned()
    }

    /// As [`Slot::state_view`], for a computed.
    fn computed_view(c: &AnyComputed) -> Option<Computed<Self>> {
        Self::computed(c).cloned()
    }
}

macro_rules! slot {
    ($t:ty, $variant:ident) => {
        impl Slot for $t {
            fn state(s: &AnySignal) -> Option<&State<Self>> {
                match s {
                    AnySignal::$variant(s) => Some(s),
                    _ => None,
                }
            }
            fn computed(c: &AnyComputed) -> Option<&Computed<Self>> {
                match c {
                    AnyComputed::$variant(c) => Some(c),
                    _ => None,
                }
            }
        }
    };
}
slot!(i32, I32);
slot!(f64, F64);
slot!(bool, Bool);
slot!(Option<String>, Str);
slot!(Value, Value);

/// `f32` properties also take `f64` signals and computeds. The view keeps the
/// source's id, so the binding stays on that signal or computed and only the
/// read narrows, as Blinc's own `f64` bindings do; a wrapping computed would
/// make a signal binding a derived one.
impl Slot for f32 {
    fn state(s: &AnySignal) -> Option<&State<Self>> {
        match s {
            AnySignal::F32(s) => Some(s),
            _ => None,
        }
    }

    fn computed(c: &AnyComputed) -> Option<&Computed<Self>> {
        match c {
            AnyComputed::F32(c) => Some(c),
            _ => None,
        }
    }

    fn state_view(s: &AnySignal) -> Option<State<Self>> {
        match s {
            AnySignal::F32(s) => Some(s.clone()),
            AnySignal::F64(s) => {
                let source = s.signal();
                Some(State::mapped(
                    source.id(),
                    Arc::new(move || source.try_get().map(|v| v as f32)),
                    global_graph(),
                    global_dirty_flag(),
                ))
            }
            _ => None,
        }
    }

    fn computed_view(c: &AnyComputed) -> Option<Computed<Self>> {
        match c {
            AnyComputed::F32(c) => Some(c.clone()),
            AnyComputed::F64(c) => {
                let source = c.clone();
                Some(Computed::mapped(
                    c.derived_id(),
                    Arc::new(move || source.try_get().map(|v| v as f32)),
                    global_graph(),
                ))
            }
            _ => None,
        }
    }
}

/// The state behind a signal handle, if it holds a `T`.
///
/// # Safety
/// `h` must be null or a `blinc_signal` handle.
pub unsafe fn state_of<'a, T: Slot>(h: *mut c_void) -> Option<&'a State<T>> {
    unsafe { handle_ref::<AnySignal>(h) }.and_then(T::state)
}

/// The computed behind a computed handle, if it holds a `T`.
///
/// # Safety
/// `h` must be null or a `blinc_computed` handle.
pub unsafe fn computed_of<'a, T: Slot>(h: *mut c_void) -> Option<&'a Computed<T>> {
    unsafe { handle_ref::<AnyComputed>(h) }.and_then(T::computed)
}

fn new_state<T: Clone + Send + 'static>(initial: T) -> State<T> {
    State::new(signal(initial), global_graph(), global_dirty_flag())
}

/// Reads through `Signal::get`, not `State::get`; see the module comment.
fn read<T: Slot>(state: &State<T>) -> T {
    state.signal().get()
}

thread_local! {
    /// What the computation in flight handed back. Nested computations finish
    /// before the outer one returns, so one slot suffices.
    static RETURNED: RefCell<Option<Box<dyn Any>>> = const { RefCell::new(None) };
}

fn give<T: 'static>(v: T) {
    RETURNED.with(|r| *r.borrow_mut() = Some(Box::new(v)));
}

fn take<T: 'static>() -> Option<T> {
    RETURNED
        .with(|r| r.borrow_mut().take())
        .and_then(|b| b.downcast::<T>().ok())
        .map(|b| *b)
}

/// A computed whose value is whatever `closure` hands back. A closure that
/// throws or returns nothing leaves the default.
fn computed_from<T: Slot>(closure: *mut c_void) -> Computed<T> {
    let closure = Rooted::new(closure);
    computed(move |_graph| {
        take::<T>();
        unsafe { call_void(closure.get()) };
        take::<T>().unwrap_or_default()
    })
}

fn computed_value<T: Slot>(c: &Computed<T>) -> T {
    c.try_get().unwrap_or_default()
}

// ============================================================================
// NUMERIC SIGNALS
// ============================================================================

macro_rules! export_numeric {
    (
        $t:ty, $variant:ident,
        $new:ident / $new_prim:ident = $new_sig:literal,
        $get:ident / $get_prim:ident = $get_sig:literal,
        $set:ident / $set_prim:ident = $set_sig:literal,
        $comp:ident / $comp_prim:ident,
        $comp_get:ident / $comp_get_prim:ident = $comp_get_sig:literal,
        $ret:ident / $ret_prim:ident = $ret_sig:literal
    ) => {
        #[unsafe(no_mangle)]
        pub extern "C" fn $new(initial: $t) -> *mut c_void {
            into_handle(AnySignal::$variant(new_state(initial)))
        }
        define_prim!($new_prim, $new, $new_sig);

        #[unsafe(no_mangle)]
        pub unsafe extern "C" fn $get(h: *mut c_void) -> $t {
            unsafe { state_of::<$t>(h) }.map(read).unwrap_or_default()
        }
        define_prim!($get_prim, $get, $get_sig);

        #[unsafe(no_mangle)]
        pub unsafe extern "C" fn $set(h: *mut c_void, v: $t) {
            if let Some(s) = unsafe { state_of::<$t>(h) } {
                s.set(v);
            }
        }
        define_prim!($set_prim, $set, $set_sig);

        #[unsafe(no_mangle)]
        pub extern "C" fn $comp(closure: *mut c_void) -> *mut c_void {
            into_handle(AnyComputed::$variant(computed_from::<$t>(closure)))
        }
        define_prim!($comp_prim, $comp, "PP_v_Xblinc_computed_");

        #[unsafe(no_mangle)]
        pub unsafe extern "C" fn $comp_get(h: *mut c_void) -> $t {
            unsafe { computed_of::<$t>(h) }
                .map(computed_value)
                .unwrap_or_default()
        }
        define_prim!($comp_get_prim, $comp_get, $comp_get_sig);

        #[unsafe(no_mangle)]
        pub extern "C" fn $ret(v: $t) {
            give(v);
        }
        define_prim!($ret_prim, $ret, $ret_sig);
    };
}

export_numeric!(
    i32,
    I32,
    hl_blinc_signal_i32 / hlp_blinc_signal_i32 = "Pi_Xblinc_signal_",
    hl_blinc_signal_get_i32 / hlp_blinc_signal_get_i32 = "PXblinc_signal__i",
    hl_blinc_signal_set_i32 / hlp_blinc_signal_set_i32 = "PXblinc_signal_i_v",
    hl_blinc_computed_i32 / hlp_blinc_computed_i32,
    hl_blinc_computed_get_i32 / hlp_blinc_computed_get_i32 = "PXblinc_computed__i",
    hl_blinc_return_i32 / hlp_blinc_return_i32 = "Pi_v"
);

export_numeric!(
    f32,
    F32,
    hl_blinc_signal_f32 / hlp_blinc_signal_f32 = "Pf_Xblinc_signal_",
    hl_blinc_signal_get_f32 / hlp_blinc_signal_get_f32 = "PXblinc_signal__f",
    hl_blinc_signal_set_f32 / hlp_blinc_signal_set_f32 = "PXblinc_signal_f_v",
    hl_blinc_computed_f32 / hlp_blinc_computed_f32,
    hl_blinc_computed_get_f32 / hlp_blinc_computed_get_f32 = "PXblinc_computed__f",
    hl_blinc_return_f32 / hlp_blinc_return_f32 = "Pf_v"
);

export_numeric!(
    f64,
    F64,
    hl_blinc_signal_f64 / hlp_blinc_signal_f64 = "Pd_Xblinc_signal_",
    hl_blinc_signal_get_f64 / hlp_blinc_signal_get_f64 = "PXblinc_signal__d",
    hl_blinc_signal_set_f64 / hlp_blinc_signal_set_f64 = "PXblinc_signal_d_v",
    hl_blinc_computed_f64 / hlp_blinc_computed_f64,
    hl_blinc_computed_get_f64 / hlp_blinc_computed_get_f64 = "PXblinc_computed__d",
    hl_blinc_return_f64 / hlp_blinc_return_f64 = "Pd_v"
);

// ============================================================================
// BOOL SIGNALS
// ============================================================================
// Arguments cross as Int: no backend declares how a narrow bool argument is
// extended, so its upper bits are not trusted.

#[unsafe(no_mangle)]
pub extern "C" fn hl_blinc_signal_bool(initial: i32) -> *mut c_void {
    into_handle(AnySignal::Bool(new_state(initial != 0)))
}
define_prim!(
    hlp_blinc_signal_bool,
    hl_blinc_signal_bool,
    "Pi_Xblinc_signal_"
);

#[unsafe(no_mangle)]
pub unsafe extern "C" fn hl_blinc_signal_get_bool(h: *mut c_void) -> bool {
    unsafe { state_of::<bool>(h) }.map(read).unwrap_or_default()
}
define_prim!(
    hlp_blinc_signal_get_bool,
    hl_blinc_signal_get_bool,
    "PXblinc_signal__b"
);

#[unsafe(no_mangle)]
pub unsafe extern "C" fn hl_blinc_signal_set_bool(h: *mut c_void, v: i32) {
    if let Some(s) = unsafe { state_of::<bool>(h) } {
        s.set(v != 0);
    }
}
define_prim!(
    hlp_blinc_signal_set_bool,
    hl_blinc_signal_set_bool,
    "PXblinc_signal_i_v"
);

#[unsafe(no_mangle)]
pub extern "C" fn hl_blinc_computed_bool(closure: *mut c_void) -> *mut c_void {
    into_handle(AnyComputed::Bool(computed_from::<bool>(closure)))
}
define_prim!(
    hlp_blinc_computed_bool,
    hl_blinc_computed_bool,
    "PP_v_Xblinc_computed_"
);

#[unsafe(no_mangle)]
pub unsafe extern "C" fn hl_blinc_computed_get_bool(h: *mut c_void) -> bool {
    unsafe { computed_of::<bool>(h) }
        .map(computed_value)
        .unwrap_or_default()
}
define_prim!(
    hlp_blinc_computed_get_bool,
    hl_blinc_computed_get_bool,
    "PXblinc_computed__b"
);

#[unsafe(no_mangle)]
pub extern "C" fn hl_blinc_return_bool(v: i32) {
    give(v != 0);
}
define_prim!(hlp_blinc_return_bool, hl_blinc_return_bool, "Pi_v");

// ============================================================================
// STRING SIGNALS
// ============================================================================
// Held in Rust as `Option<String>`, so property bindings can read them and
// null survives. They cross as NUL-terminated UTF-8, null as a null pointer.

fn opt_string_to_hl(s: Option<String>) -> *mut vbyte {
    s.map_or(std::ptr::null_mut(), |s| string_to_hl(&s))
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn hl_blinc_signal_string(initial: *const vbyte) -> *mut c_void {
    into_handle(AnySignal::Str(new_state(unsafe {
        opt_string_from(initial)
    })))
}
define_prim!(
    hlp_blinc_signal_string,
    hl_blinc_signal_string,
    "PB_Xblinc_signal_"
);

#[unsafe(no_mangle)]
pub unsafe extern "C" fn hl_blinc_signal_get_string(h: *mut c_void) -> *mut vbyte {
    opt_string_to_hl(unsafe { state_of::<Option<String>>(h) }.and_then(read))
}
define_prim!(
    hlp_blinc_signal_get_string,
    hl_blinc_signal_get_string,
    "PXblinc_signal__B"
);

#[unsafe(no_mangle)]
pub unsafe extern "C" fn hl_blinc_signal_set_string(h: *mut c_void, v: *const vbyte) {
    if let Some(s) = unsafe { state_of::<Option<String>>(h) } {
        s.set(unsafe { opt_string_from(v) });
    }
}
define_prim!(
    hlp_blinc_signal_set_string,
    hl_blinc_signal_set_string,
    "PXblinc_signal_B_v"
);

#[unsafe(no_mangle)]
pub extern "C" fn hl_blinc_computed_string(closure: *mut c_void) -> *mut c_void {
    into_handle(AnyComputed::Str(computed_from::<Option<String>>(closure)))
}
define_prim!(
    hlp_blinc_computed_string,
    hl_blinc_computed_string,
    "PP_v_Xblinc_computed_"
);

#[unsafe(no_mangle)]
pub unsafe extern "C" fn hl_blinc_computed_get_string(h: *mut c_void) -> *mut vbyte {
    opt_string_to_hl(unsafe { computed_of::<Option<String>>(h) }.and_then(computed_value))
}
define_prim!(
    hlp_blinc_computed_get_string,
    hl_blinc_computed_get_string,
    "PXblinc_computed__B"
);

#[unsafe(no_mangle)]
pub unsafe extern "C" fn hl_blinc_return_string(v: *const vbyte) {
    give(unsafe { opt_string_from(v) });
}
define_prim!(hlp_blinc_return_string, hl_blinc_return_string, "PB_v");

// ============================================================================
// VALUE SIGNALS (brush, color, radius, transform, shadow)
// ============================================================================
// Haxe keeps the wrapper object it set and returns that from `get`, so there
// are no value getters; `blinc_signal_touch` records the read.

/// # Safety
/// `h` must be null or a `blinc_value` handle.
unsafe fn value_of(h: *mut c_void) -> Value {
    unsafe { handle_ref::<Value>(h) }
        .cloned()
        .unwrap_or_default()
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn hl_blinc_signal_value(initial: *mut c_void) -> *mut c_void {
    into_handle(AnySignal::Value(new_state(unsafe { value_of(initial) })))
}
define_prim!(
    hlp_blinc_signal_value,
    hl_blinc_signal_value,
    "PXblinc_value__Xblinc_signal_"
);

#[unsafe(no_mangle)]
pub unsafe extern "C" fn hl_blinc_signal_set_value(h: *mut c_void, v: *mut c_void) {
    if let Some(s) = unsafe { state_of::<Value>(h) } {
        s.set(unsafe { value_of(v) });
    }
}
define_prim!(
    hlp_blinc_signal_set_value,
    hl_blinc_signal_set_value,
    "PXblinc_signal_Xblinc_value__v"
);

#[unsafe(no_mangle)]
pub extern "C" fn hl_blinc_computed_value(closure: *mut c_void) -> *mut c_void {
    into_handle(AnyComputed::Value(computed_from::<Value>(closure)))
}
define_prim!(
    hlp_blinc_computed_value,
    hl_blinc_computed_value,
    "PP_v_Xblinc_computed_"
);

#[unsafe(no_mangle)]
pub unsafe extern "C" fn hl_blinc_return_value(v: *mut c_void) {
    give(unsafe { value_of(v) });
}
define_prim!(
    hlp_blinc_return_value,
    hl_blinc_return_value,
    "PXblinc_value__v"
);

// ============================================================================
// ANY TYPE
// ============================================================================

/// Read a signal for its side effect alone: inside a computation, recording
/// it as a dependency.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn hl_blinc_signal_touch(h: *mut c_void) {
    match unsafe { handle_ref::<AnySignal>(h) } {
        Some(AnySignal::I32(s)) => {
            read(s);
        }
        Some(AnySignal::F32(s)) => {
            read(s);
        }
        Some(AnySignal::F64(s)) => {
            read(s);
        }
        Some(AnySignal::Bool(s)) => {
            read(s);
        }
        Some(AnySignal::Str(s)) => {
            read(s);
        }
        Some(AnySignal::Value(s)) => {
            read(s);
        }
        None => {}
    }
}
define_prim!(
    hlp_blinc_signal_touch,
    hl_blinc_signal_touch,
    "PXblinc_signal__v"
);

/// Release a computed before its handle is collected, as its owner does when
/// disposed. Queued like a finalizer's release, so it takes effect at the next
/// flush; releasing the same computed again is a no-op there.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn hl_blinc_computed_release(h: *mut c_void) {
    if let Some(c) = unsafe { handle_ref::<AnyComputed>(h) } {
        c.release();
    }
}
define_prim!(
    hlp_blinc_computed_release,
    hl_blinc_computed_release,
    "PXblinc_computed__v"
);

/// Bring a computed up to date, running its closure if a dependency changed.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn hl_blinc_computed_touch(h: *mut c_void) {
    match unsafe { handle_ref::<AnyComputed>(h) } {
        Some(AnyComputed::I32(c)) => {
            c.try_get();
        }
        Some(AnyComputed::F32(c)) => {
            c.try_get();
        }
        Some(AnyComputed::F64(c)) => {
            c.try_get();
        }
        Some(AnyComputed::Bool(c)) => {
            c.try_get();
        }
        Some(AnyComputed::Str(c)) => {
            c.try_get();
        }
        Some(AnyComputed::Value(c)) => {
            c.try_get();
        }
        None => {}
    }
}
define_prim!(
    hlp_blinc_computed_touch,
    hl_blinc_computed_touch,
    "PXblinc_computed__v"
);

// ============================================================================
// EFFECTS
// ============================================================================
// What a Haxe `Watch` tracks with: an effect whose body is a Haxe closure.
// Blinc runs it once at creation and again, inside the graph lock, whenever
// a signal or computed it read changes. The closure only reads and records;
// reacting waits for the next flush, outside the lock.

pub struct WatchEffect(Effect);

impl WatchEffect {
    fn release(&self) {
        RELEASED_EFFECTS
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .push(self.0);
    }
}

impl Drop for WatchEffect {
    fn drop(&mut self) {
        self.release();
    }
}

/// Not to be called from inside a computation or effect: creating an effect
/// takes the graph lock.
#[unsafe(no_mangle)]
pub extern "C" fn hl_blinc_effect(closure: *mut c_void) -> *mut c_void {
    let closure = Rooted::new(closure);
    let e = effect(move |_graph| unsafe { call_void(closure.get()) });
    into_handle(WatchEffect(e))
}
define_prim!(hlp_blinc_effect, hl_blinc_effect, "PP_v_Xblinc_effect_");

/// Stop an effect before its handle is collected; it is removed at the next
/// flush, like a released computed.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn hl_blinc_effect_release(h: *mut c_void) {
    if let Some(w) = unsafe { handle_ref::<WatchEffect>(h) } {
        w.release();
    }
}
define_prim!(
    hlp_blinc_effect_release,
    hl_blinc_effect_release,
    "PXblinc_effect__v"
);

// ============================================================================
// RENDER LOOP
// ============================================================================

/// Whether any state changed since the last `blinc_clear_dirty`.
#[unsafe(no_mangle)]
pub extern "C" fn hl_blinc_is_dirty() -> bool {
    global_dirty_flag().load(Ordering::Relaxed)
}
define_prim!(hlp_blinc_is_dirty, hl_blinc_is_dirty, "P_b");

#[unsafe(no_mangle)]
pub extern "C" fn hl_blinc_clear_dirty() {
    global_dirty_flag().store(false, Ordering::Relaxed);
}
define_prim!(hlp_blinc_clear_dirty, hl_blinc_clear_dirty, "P_v");
