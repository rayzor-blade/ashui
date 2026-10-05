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
