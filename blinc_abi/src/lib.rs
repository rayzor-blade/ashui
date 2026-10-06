// Every `unsafe extern "C"` export here is called only by the HashLink
// runtime, and its contract is the matching Haxe extern declaration.
#![allow(clippy::missing_safety_doc)]

#[cfg(target_os = "macos")]
mod alloc;
#[cfg(target_os = "macos")]
#[global_allocator]
static ALLOCATOR: alloc::BigBlocksMapped = alloc::BigBlocksMapped;

pub mod bitmap;
mod display_list;
mod grid;
mod hit;
mod hl;
pub mod layout_router;
pub mod node;
pub mod reactive;
pub mod svg;
pub mod text;
pub mod types;

/// Tells Ash this library never stores a GC pointer into a GC object itself:
/// it keeps Haxe objects only through roots (`hl::Rooted`) and writes numbers
/// into byte buffers. Ash's card-marking write barrier is then safe with it
/// loaded.
#[unsafe(no_mangle)]
pub static ash_hdll_barrier_aware: u8 = 1;
