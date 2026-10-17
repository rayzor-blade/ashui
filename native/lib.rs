//! Package the upstream HashLink adapter under the library name used by Haxe.
//! The implementation and native linking configuration live in blinc_abi.
//! For wasm it is the side module `blinc_abi.wasm` (scripts/build_wasm.sh).

#![cfg_attr(all(target_arch = "wasm32", target_feature = "atomics"), feature(thread_local))]

pub use blinc_abi_core::*;

// The side module allocates from the program's heap, so a pointer that crosses
// the boundary has one owner.
#[cfg(target_family = "wasm")]
#[global_allocator]
static ALLOCATOR: hl_abi::ProgramAllocator = hl_abi::ProgramAllocator;

// A side module cannot import the TLS errno that threaded WASI's std
// addresses, and nothing here reports through it.
#[cfg(target_family = "wasm")]
#[unsafe(no_mangle)]
#[cfg_attr(target_feature = "atomics", thread_local)]
static mut errno: i32 = 0;
