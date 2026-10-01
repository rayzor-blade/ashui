
use hl_abi::{define_prim, varray, vbyte, vdynamic};
use blinc_core::reactive::{signal, computed, global_dirty_flag, Signal, Computed};
use std::{ptr, sync::atomic::Ordering};

macro_rules! hl_export_signal_global {
    (
        $type:ty, 
        // 1. Allocation
        $new_fn:ident, $new_prim:ident, $new_sig:expr,
        
        // 2. Read
        $get_fn:ident, $get_prim:ident, $get_sig:expr,
        
        // 3. Write
        $set_fn:ident, $set_prim:ident, $set_sig:expr,
        
        // 4. Drop Signal
        $drop_fn:ident, $drop_prim:ident, $drop_sig:expr,
        
        // 5. Computed (Derived)
        $computed_fn:ident, $computed_prim:ident, $computed_sig:expr,
        
        // 6. Drop Computed
        $computed_drop_fn:ident, $computed_drop_prim:ident, $computed_drop_sig:expr
    ) => {
        // 1. Allocation (implicitly uses GLOBAL_GRAPH)
        #[unsafe(no_mangle)]
        pub extern "C" fn $new_fn(initial: $type) -> *mut Signal<$type> {
            let sig = signal(initial);
            Box::into_raw(Box::new(sig))
        }
        define_prim!($new_prim, $new_fn, $new_sig);

        // 2. Read (implicitly uses GLOBAL_GRAPH)
        #[unsafe(no_mangle)]
        pub extern "C" fn $get_fn(sig_ptr: *const Signal<$type>) -> $type {
            let sig = unsafe { &*sig_ptr };
            sig.get() 
        }
        define_prim!($get_prim, $get_fn, $get_sig);

        // 3. Write (implicitly updates GLOBAL_GRAPH and sets GLOBAL_DIRTY)
        #[unsafe(no_mangle)]
        pub extern "C" fn $set_fn(sig_ptr: *mut Signal<$type>, val: $type) {
            let sig = unsafe { &*sig_ptr };
            sig.set(val);
        }
        define_prim!($set_prim, $set_fn, $set_sig);

        // 4. Drop Signal
        #[unsafe(no_mangle)]
        pub extern "C" fn $drop_fn(sig_ptr: *mut Signal<$type>) {
            if !sig_ptr.is_null() {
                unsafe { let _ = Box::from_raw(sig_ptr); }
            }
        }
        define_prim!($drop_prim, $drop_fn, $drop_sig);
       

        // 5. Computed (The Blinc term for Derived)
        #[unsafe(no_mangle)]
        pub extern "C" fn $computed_fn(
            parent_ptr: *const Signal<$type>,
            ctx_id: usize, // Haxe closure registry ID
            compute_callback: extern "C" fn(usize, $type) -> $type
        ) -> *mut Computed<$type> {
            
            let parent = unsafe { &*parent_ptr }.clone();
            
            // Blinc passes the graph context into the closure (e.g., `SharedReactiveGraph`)
            // This prevents deadlocks when reading `parent` inside the computation cycle.
            let comp = computed(move |graph| {
                
                // Read the parent value using the provided graph context.
                // Depending on Blinc's exact API, this is either:
                // parent.get_with(graph) OR the signal implicitly uses the passed Arc
                let current_val = graph.get(parent); // or parent.get_with(graph)
                
                // Jump across the C ABI to Haxe to run the pure math/logic.
                // Haxe is completely isolated from the Rust Mutex/Arc lifecycle.
                compute_callback(ctx_id, current_val.unwrap_or_default()) // Handle Option<$type> if needed
            });
            
            Box::into_raw(Box::new(comp))
        }
         define_prim!($computed_prim, $computed_fn, $computed_sig);

        // 6. Drop Computed
        #[unsafe(no_mangle)]
        pub extern "C" fn $computed_drop_fn(comp_ptr: *mut Computed<$type>) {
            if !comp_ptr.is_null() {
                unsafe { let _ = Box::from_raw(comp_ptr); }
            }
        }
        define_prim!($computed_drop_prim, $computed_drop_fn, $computed_drop_sig);
    };
}

// Export the primitives
hl_export_signal_global!(
    i32,
    
    // new(initial: i32) -> *mut Signal<i32> 
    // Returns Pointer, Takes Int
    hl_blinc_signal_new_i32, hlp_blinc_signal_new_i32, "P_I",
    
    // get(sig: *const Signal) -> i32
    // Returns Int, Takes Pointer
    hl_blinc_signal_get_i32, hlp_blinc_signal_get_i32, "I_P",
    
    // set(sig: *mut Signal, val: i32) -> void
    // Returns Void, Takes Pointer + Int
    hl_blinc_signal_set_i32, hlp_blinc_signal_set_i32, "V_PI",
    
    // drop(sig: *mut Signal) -> void
    // Returns Void, Takes Pointer
    hl_blinc_signal_drop_i32, hlp_blinc_signal_drop_i32, "V_P",
    
    // computed(parent: *const Signal, ctx: usize, fn) -> *mut Computed<i32>
    // Returns Pointer, Takes Pointer + Int + Pointer(Closure)
    hl_blinc_computed_i32, hlp_blinc_computed_i32, "P_PIP",
    
    // drop_computed(comp: *mut Computed) -> void
    // Returns Void, Takes Pointer
    hl_blinc_computed_drop_i32, hlp_blinc_computed_drop_i32, "V_P"
);


hl_export_signal_global!(
    f32,
    
    // new(initial: i32) -> *mut Signal<i32> 
    // Returns Pointer, Takes Int
    hl_blinc_signal_new_f32, hlp_blinc_signal_new_f32, "P_F",
    
    // get(sig: *const Signal) -> i32
    // Returns Int, Takes Pointer
    hl_blinc_signal_get_f32, hlp_blinc_signal_get_f32, "F_P",
    
    // set(sig: *mut Signal, val: i32) -> void
    // Returns Void, Takes Pointer + Int
    hl_blinc_signal_set_f32, hlp_blinc_signal_set_f32, "V_PF",
    
    // drop(sig: *mut Signal) -> void
    // Returns Void, Takes Pointer
    hl_blinc_signal_drop_f32, hlp_blinc_signal_drop_f32, "V_P",
    
    // computed(parent: *const Signal, ctx: usize, fn) -> *mut Computed<i32>
    // Returns Pointer, Takes Pointer + Int + Pointer(Closure)
    hl_blinc_computed_f32, hlp_blinc_computed_f32, "P_PIP",
    
    // drop_computed(comp: *mut Computed) -> void
    // Returns Void, Takes Pointer
    hl_blinc_computed_drop_f32, hlp_blinc_computed_drop_f32, "V_P"
);

hl_export_signal_global!(
    f64,
    hl_blinc_signal_new_f64, hlp_blinc_signal_new_f64, "P_D",
    hl_blinc_signal_get_f64, hlp_blinc_signal_get_f64, "D_P",
    hl_blinc_signal_set_f64, hlp_blinc_signal_set_f64, "V_PD",
    hl_blinc_signal_drop_f64, hlp_blinc_signal_drop_f64, "V_P",
    hl_blinc_computed_f64, hlp_blinc_computed_f64, "P_PDP",
    hl_blinc_computed_drop_f64, hlp_blinc_computed_drop_f64, "V_P"
);


// --- The Global Render Loop Optimization ---

/// Haxe can poll this every frame to know if it needs to re-render
#[unsafe(no_mangle)]
pub extern "C" fn hl_blinc_is_dirty() -> bool {
    let dirty_flag = global_dirty_flag();
    dirty_flag.load(Ordering::Relaxed)
}
define_prim!(hlp_blinc_is_dirty, hl_blinc_is_dirty, "B_V");

/// Reset the dirty flag (typically called right before calculating layout)
#[unsafe(no_mangle)]
pub extern "C" fn hl_blinc_clear_dirty() {
    let dirty_flag = global_dirty_flag();
    dirty_flag.store(false, Ordering::Relaxed);
}
define_prim!(hlp_blinc_clear_dirty, hl_blinc_clear_dirty, "V_V");



/// A thread-safe wrapper for HashLink GC pointers.
/// We promise the Rust compiler that we won't mutate the GC memory directly 
/// off the main thread (HashLink is single-threaded anyway).
#[derive(Clone, Copy)]
#[repr(transparent)]
pub struct HlDynamic(pub *mut vdynamic);

impl Default for HlDynamic {
    fn default() -> Self {
        HlDynamic(ptr::null_mut())
    }
}

unsafe impl Send for HlDynamic {}
unsafe impl Sync for HlDynamic {}

// 1. Allocation
#[unsafe(no_mangle)]
pub unsafe extern "C" fn hl_blinc_signal_new_dynamic(initial: *mut vdynamic) -> *mut Signal<HlDynamic> {
    Box::into_raw(Box::new(signal(HlDynamic(initial))))
}
// "P_D" -> Returns Pointer (P), Takes Dynamic (D)
define_prim!(hlp_signal_new_dynamic, hl_blinc_signal_new_dynamic, "P_D");

// 2. Read
#[unsafe(no_mangle)]
pub unsafe extern "C" fn hl_blinc_signal_get_dynamic(sig_ptr: *const Signal<HlDynamic>) -> *mut vdynamic {
    unsafe { &*sig_ptr }.get().0
}
// "D_P" -> Returns Dynamic (D), Takes Pointer (P)
define_prim!(hlp_signal_get_dynamic, hl_blinc_signal_get_dynamic, "D_P");

// 3. Write
#[unsafe(no_mangle)]
pub unsafe extern "C" fn hl_blinc_signal_set_dynamic(sig_ptr: *mut Signal<HlDynamic>, val: *mut vdynamic) {
    unsafe { &*sig_ptr }.set(HlDynamic(val));
}
// "V_PD" -> Returns Void (V), Takes Pointer (P) + Dynamic (D)
define_prim!(hlp_signal_set_dynamic, hl_blinc_signal_set_dynamic, "V_PD");

// 4. Drop Signal
#[unsafe(no_mangle)]
pub unsafe extern "C" fn hl_blinc_signal_drop_dynamic(sig_ptr: *mut Signal<HlDynamic>) {
    if !sig_ptr.is_null() {
        unsafe { let _ = Box::from_raw(sig_ptr); }
    }
}
define_prim!(hlp_signal_drop_dynamic, hl_blinc_signal_drop_dynamic, "V_P");

// 5. Computed (Derived Dynamic)
#[unsafe(no_mangle)]
pub unsafe extern "C" fn hl_blinc_computed_dynamic(
    parent_ptr: *const Signal<HlDynamic>,
    ctx_id: usize,
    compute_callback: unsafe extern "C" fn(usize, *mut vdynamic) -> *mut vdynamic
) -> *mut Computed<HlDynamic> {
    let parent = unsafe { &*parent_ptr }.clone();
    
    let comp = computed(move |graph| {
        let current_val = graph.get(parent);
        let new_val = unsafe { compute_callback(ctx_id, current_val.unwrap_or_default().0) };
        HlDynamic(new_val)
    });
    
    Box::into_raw(Box::new(comp))
}
// "P_PDP" -> Returns Pointer, Takes Pointer + Dynamic(ctx/usize mapped to Int in HL) + Pointer(Callback)
define_prim!(hlp_computed_dynamic, hl_blinc_computed_dynamic, "P_PIP"); 
// Note: HashLink treats `usize` as Int (I) and function callbacks as opaque Pointers (P).

// 6. Drop Computed
#[unsafe(no_mangle)]
pub unsafe extern "C" fn hl_blinc_computed_drop_dynamic(comp_ptr: *mut Computed<HlDynamic>) {
    if !comp_ptr.is_null() {
        unsafe { let _ = Box::from_raw(comp_ptr); }
    }
}
define_prim!(hlp_computed_drop_dynamic, hl_blinc_computed_drop_dynamic, "V_P");





// ============================================================================
// BYTES WRAPPER (For hl.Bytes / Strings)
// ============================================================================

#[derive(Clone, Copy)]
#[repr(transparent)]
pub struct HlBytes(pub *mut vbyte);

unsafe impl Send for HlBytes {}
unsafe impl Sync for HlBytes {}
impl Default for HlBytes { fn default() -> Self { HlBytes(ptr::null_mut()) } }

// 1. Allocation ("P_B" -> Returns Pointer, Takes Bytes)
#[unsafe(no_mangle)]
pub unsafe extern "C" fn hl_blinc_signal_new_bytes(initial: *mut vbyte) -> *mut Signal<HlBytes> {
    Box::into_raw(Box::new(signal(HlBytes(initial))))
}
define_prim!(hlp_blinc_signal_new_bytes, hl_blinc_signal_new_bytes, "P_B");

// 2. Read ("B_P" -> Returns Bytes, Takes Pointer)
#[unsafe(no_mangle)]
pub unsafe extern "C" fn hl_blinc_signal_get_bytes(sig_ptr: *const Signal<HlBytes>) -> *mut vbyte {
    unsafe { &*sig_ptr }.get().0
}
define_prim!(hlp_blinc_signal_get_bytes, hl_blinc_signal_get_bytes, "B_P");

// 3. Write ("V_PB" -> Returns Void, Takes Pointer + Bytes)
#[unsafe(no_mangle)]
pub unsafe extern "C" fn hl_blinc_signal_set_bytes(sig_ptr: *mut Signal<HlBytes>, val: *mut vbyte) {
    unsafe { &*sig_ptr }.set(HlBytes(val));
}
define_prim!(hlp_blinc_signal_set_bytes, hl_blinc_signal_set_bytes, "V_PB");

// 4. Drop
#[unsafe(no_mangle)]
pub unsafe extern "C" fn hl_blinc_signal_drop_bytes(sig_ptr: *mut Signal<HlBytes>) {
    if !sig_ptr.is_null() { unsafe { let _ = Box::from_raw(sig_ptr); } }
}
define_prim!(hlp_blinc_signal_drop_bytes, hl_blinc_signal_drop_bytes, "V_P");

// 5. Computed Bytes ("P_PIP" -> Returns Pointer, Takes Pointer + Int(ctx) + Pointer(Callback))
#[unsafe(no_mangle)]
pub unsafe extern "C" fn hl_blinc_computed_bytes(
    parent_ptr: *const Signal<HlBytes>,
    ctx_id: usize,
    compute_callback: unsafe extern "C" fn(usize, *mut vbyte) -> *mut vbyte
) -> *mut Computed<HlBytes> {
    let parent = unsafe { &*parent_ptr }.clone();
    let comp = computed(move |graph| {
        let current_val = graph.get(parent);
        let new_val = unsafe { compute_callback(ctx_id, current_val.unwrap_or_default().0) };
        HlBytes(new_val)
    });
    Box::into_raw(Box::new(comp))
}
define_prim!(hlp_blinc_computed_bytes, hl_blinc_computed_bytes, "P_PIP"); 

// 6. Drop Computed Bytes
#[unsafe(no_mangle)]
pub unsafe extern "C" fn hl_blinc_computed_drop_bytes(comp_ptr: *mut Computed<HlBytes>) {
    if !comp_ptr.is_null() { unsafe { let _ = Box::from_raw(comp_ptr); } }
}
define_prim!(hlp_blinc_computed_drop_bytes, hl_blinc_computed_drop_bytes, "V_P");


// ============================================================================
// ARRAY WRAPPER (For hl.NativeArray / varray)
// ============================================================================

#[derive(Clone, Copy)]
#[repr(transparent)]
pub struct HlArray(pub *mut varray);

unsafe impl Send for HlArray {}
unsafe impl Sync for HlArray {}
impl Default for HlArray { fn default() -> Self { HlArray(ptr::null_mut()) } }

// 1. Allocation ("P_A" -> Returns Pointer, Takes Array)
#[unsafe(no_mangle)]
pub unsafe extern "C" fn hl_blinc_signal_new_array(initial: *mut varray) -> *mut Signal<HlArray> {
    Box::into_raw(Box::new(signal(HlArray(initial))))
}
define_prim!(hlp_blinc_signal_new_array, hl_blinc_signal_new_array, "P_A");

// 2. Read ("A_P" -> Returns Array, Takes Pointer)
#[unsafe(no_mangle)]
pub unsafe extern "C" fn hl_blinc_signal_get_array(sig_ptr: *const Signal<HlArray>) -> *mut varray {
    unsafe { &*sig_ptr }.get().0
}
define_prim!(hlp_blinc_signal_get_array, hl_blinc_signal_get_array, "A_P");

// 3. Write ("V_PA" -> Returns Void, Takes Pointer + Array)
#[unsafe(no_mangle)]
pub unsafe extern "C" fn hl_blinc_signal_set_array(sig_ptr: *mut Signal<HlArray>, val: *mut varray) {
    unsafe { &*sig_ptr }.set(HlArray(val));
}
define_prim!(hlp_blinc_signal_set_array, hl_blinc_signal_set_array, "V_PA");

// 4. Drop
#[unsafe(no_mangle)]
pub unsafe extern "C" fn hl_blinc_signal_drop_array(sig_ptr: *mut Signal<HlArray>) {
    if !sig_ptr.is_null() { unsafe { let _ = Box::from_raw(sig_ptr); } }
}
define_prim!(hlp_blinc_signal_drop_array, hl_blinc_signal_drop_array, "V_P");

// 5. Computed Array
#[unsafe(no_mangle)]
pub unsafe extern "C" fn hl_blinc_computed_array(
    parent_ptr: *const Signal<HlArray>,
    ctx_id: usize,
    compute_callback: unsafe extern "C" fn(usize, *mut varray) -> *mut varray
) -> *mut Computed<HlArray> {
    let parent = unsafe { &*parent_ptr }.clone();
    let comp = computed(move |graph| {
        let current_val = graph.get(parent);
        let new_val = unsafe { compute_callback(ctx_id, current_val.unwrap_or_default().0) };
        HlArray(new_val)
    });
    Box::into_raw(Box::new(comp))
}
define_prim!(hlp_blinc_computed_array, hl_blinc_computed_array, "P_PIP"); 

// 6. Drop Computed Array
#[unsafe(no_mangle)]
pub unsafe extern "C" fn hl_blinc_computed_drop_array(comp_ptr: *mut Computed<HlArray>) {
    if !comp_ptr.is_null() { unsafe { let _ = Box::from_raw(comp_ptr); } }
}
define_prim!(hlp_blinc_computed_drop_array, hl_blinc_computed_drop_array, "V_P");