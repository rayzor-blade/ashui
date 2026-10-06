//! The HashLink runtime as this library uses it: GC-owned handles, rooted
//! pointers, strings, and calls back into Haxe.
//!
//! Only upstream `hl.h` names are imported. Ash exports them with the same
//! meaning, so one build runs under either runtime.

use hl_abi::{hl_alloc_bytes, hl_type, vbyte, vdynamic};
use std::ffi::{CStr, c_char, c_void};
use std::ptr;

/// `hl.h`'s `MEM_KIND_FINALIZER`: word zero of the block is a callback the
/// collector runs once the block is unreachable.
const MEM_KIND_FINALIZER: i32 = 3;

/// Opaque: only ever passed back to `hl_dyn_call`.
#[repr(C)]
pub struct vclosure {
    _private: [u8; 0],
}

unsafe extern "C" {
    #[cfg(not(windows))]
    static mut hlt_abstract: hl_type;
    #[cfg(windows)]
    #[link_name = "__imp_hlt_abstract"]
    static mut hlt_abstract_import: *mut hl_type;

    fn hl_gc_alloc_gen(t: *mut hl_type, size: i32, flags: i32) -> *mut c_void;
    fn hl_add_root(slot: *mut c_void);
    fn hl_remove_root(slot: *mut c_void);
    fn hl_dyn_call(c: *mut vclosure, args: *mut *mut vdynamic, nargs: i32) -> *mut vdynamic;
    fn hl_blocking(enter: bool);
}

fn abstract_type() -> *mut hl_type {
    #[cfg(windows)]
    unsafe {
        hlt_abstract_import
    }
    #[cfg(not(windows))]
    {
        ptr::addr_of_mut!(hlt_abstract)
    }
}

// ============================================================================
// HANDLES
// ============================================================================

/// A GC block owning one boxed Rust value, seen from Haxe as an
/// `hl.Abstract<...>`. The collector calls `finalize` once Haxe can no longer
/// reach the block, which drops the box.
///
/// Dropping `T` must not call into the runtime: stock HashLink runs
/// finalizers inside the collection.
#[repr(C)]
struct Block<T> {
    finalize: unsafe extern "C" fn(*mut c_void),
    value: *mut T,
}

unsafe extern "C" fn finalize<T>(block: *mut c_void) {
    let block = block as *mut Block<T>;
    let value = unsafe { ptr::replace(ptr::addr_of_mut!((*block).value), ptr::null_mut()) };
    if !value.is_null() {
        drop(unsafe { Box::from_raw(value) });
    }
}

/// Move `value` into a new GC-owned handle.
pub fn into_handle<T>(value: T) -> *mut c_void {
    unsafe {
        let block = hl_gc_alloc_gen(
            abstract_type(),
            std::mem::size_of::<Block<T>>() as i32,
            MEM_KIND_FINALIZER,
        ) as *mut Block<T>;
        if block.is_null() {
            return ptr::null_mut();
        }
        block.write(Block {
            finalize: finalize::<T>,
            value: Box::into_raw(Box::new(value)),
        });
        block.cast()
    }
}

/// The value inside a handle made by [`into_handle::<T>`], or `None` for null.
///
/// # Safety
/// `handle` must be null or a handle holding a `T`. The Haxe externs give each
/// `T` its own abstract type, which is what keeps the two in step.
pub unsafe fn handle_ref<'a, T>(handle: *mut c_void) -> Option<&'a T> {
    if handle.is_null() {
        return None;
    }
    unsafe { (*(handle as *mut Block<T>)).value.as_ref() }
}

/// Take the value out of a handle made by [`into_handle::<T>`], leaving it
/// empty: the finalizer then has nothing to drop, and later reads find
/// nothing.
///
/// # Safety
/// As [`handle_ref`], and no reference into the handle may be live.
pub unsafe fn take_handle<T>(handle: *mut c_void) -> Option<Box<T>> {
    if handle.is_null() {
        return None;
    }
    let value = unsafe {
        ptr::replace(
            ptr::addr_of_mut!((*(handle as *mut Block<T>)).value),
            ptr::null_mut(),
        )
    };
    if value.is_null() {
        None
    } else {
        Some(unsafe { Box::from_raw(value) })
    }
}

/// As [`handle_ref`], mutably.
///
/// # Safety
/// As [`handle_ref`], and no other reference into the handle may be live.
pub unsafe fn handle_mut<'a, T>(handle: *mut c_void) -> Option<&'a mut T> {
    if handle.is_null() {
        return None;
    }
    unsafe { (*(handle as *mut Block<T>)).value.as_mut() }
}

// ============================================================================
// ROOTS AND CALLBACKS
// ============================================================================

/// A GC pointer held from Rust. It lives in its own heap slot registered as a
/// root, so the object survives for as long as this value does.
pub struct Rooted(Box<*mut c_void>);

// The runtime is single-threaded; Blinc only asks for these bounds because its
// graph is shareable in general.
unsafe impl Send for Rooted {}
unsafe impl Sync for Rooted {}

impl Rooted {
    pub fn new(p: *mut c_void) -> Self {
        let mut slot = Box::new(p);
        unsafe { hl_add_root(ptr::addr_of_mut!(*slot).cast()) };
        Rooted(slot)
    }

    pub fn get(&self) -> *mut c_void {
        *self.0
    }
}

impl Drop for Rooted {
    fn drop(&mut self) {
        unsafe { hl_remove_root(ptr::addr_of_mut!(*self.0).cast()) };
    }
}

/// Call a Haxe `Void->Void` closure.
///
/// Through `hl_dyn_call` rather than the closure's code pointer: under Ash's
/// interpreter that pointer is a function index, not an address. The Haxe
/// side catches its own exceptions, so none unwinds through Rust frames.
///
/// # Safety
/// `closure` must be a live `Void->Void` closure.
pub unsafe fn call_void(closure: *mut c_void) {
    unsafe { hl_dyn_call(closure.cast(), ptr::null_mut(), 0) };
}

/// This thread marked as blocking while the value lives, so a collection goes
/// ahead without waiting for it. Only for long work that allocates nothing on
/// the GC heap and touches no GC object but byte buffers its caller keeps
/// alive. Make it before taking any lock the work holds, so the lock is
/// released before the thread stops blocking.
pub struct Blocking(());

impl Blocking {
    pub fn enter() -> Self {
        unsafe { hl_blocking(true) };
        Blocking(())
    }
}

impl Drop for Blocking {
    fn drop(&mut self) {
        unsafe { hl_blocking(false) };
    }
}

// ============================================================================
// STRINGS
// ============================================================================

/// A Rust string from NUL-terminated UTF-8, as Haxe's `String.toUtf8()`
/// produces. Null reads as empty.
///
/// # Safety
/// `bytes` must be null or NUL-terminated.
pub unsafe fn string_from(bytes: *const vbyte) -> String {
    if bytes.is_null() {
        return String::new();
    }
    unsafe { CStr::from_ptr(bytes as *const c_char) }
        .to_string_lossy()
        .into_owned()
}

/// As [`string_from`], keeping null distinct from empty.
///
/// # Safety
/// As [`string_from`].
pub unsafe fn opt_string_from(bytes: *const vbyte) -> Option<String> {
    if bytes.is_null() {
        None
    } else {
        Some(unsafe { string_from(bytes) })
    }
}

/// GC-allocated NUL-terminated UTF-8, for `String.fromUTF8` on the Haxe side.
pub fn string_to_hl(s: &str) -> *mut vbyte {
    unsafe {
        let len = s.len();
        let out = hl_alloc_bytes(len as i32 + 1);
        if !out.is_null() {
            ptr::copy_nonoverlapping(s.as_ptr(), out, len);
            *out.add(len) = 0;
        }
        out
    }
}
