//! The library's allocator on macOS: blocks of a megabyte or more, as a
//! decoded photo's pixels and an image decoder's buffers are, mapped from
//! the system and unmapped when freed; smaller ones from malloc. macOS's
//! malloc keeps freed large blocks resident and counted against the
//! process, a hundred megabytes and more after a few photos, and does not
//! give them back when asked. Elsewhere malloc maps and unmaps large blocks
//! itself, so this is macOS's alone.

use std::alloc::{GlobalAlloc, Layout, System};

const BIG: usize = 1 << 20;
const PAGE: usize = 16 * 1024;

unsafe extern "C" {
    fn mmap(addr: *mut u8, len: usize, prot: i32, flags: i32, fd: i32, offset: i64) -> *mut u8;
    fn munmap(addr: *mut u8, len: usize) -> i32;
}

const PROT_READ_WRITE: i32 = 1 | 2;
const MAP_PRIVATE_ANON: i32 = 0x0002 | 0x1000;
const MAP_FAILED: *mut u8 = !0usize as *mut u8;

pub struct BigBlocksMapped;

#[inline]
fn mapped(layout: &Layout) -> bool {
    layout.size() >= BIG && layout.align() <= PAGE
}

unsafe impl GlobalAlloc for BigBlocksMapped {
    unsafe fn alloc(&self, layout: Layout) -> *mut u8 {
        if mapped(&layout) {
            let p = unsafe { mmap(std::ptr::null_mut(), layout.size(), PROT_READ_WRITE, MAP_PRIVATE_ANON, -1, 0) };
            return if p == MAP_FAILED { std::ptr::null_mut() } else { p };
        }
        unsafe { System.alloc(layout) }
    }

    unsafe fn alloc_zeroed(&self, layout: Layout) -> *mut u8 {
        // Mapped pages start zeroed.
        if mapped(&layout) {
            return unsafe { self.alloc(layout) };
        }
        unsafe { System.alloc_zeroed(layout) }
    }

    unsafe fn dealloc(&self, ptr: *mut u8, layout: Layout) {
        if mapped(&layout) {
            unsafe { munmap(ptr, layout.size()) };
            return;
        }
        unsafe { System.dealloc(ptr, layout) }
    }

    unsafe fn realloc(&self, ptr: *mut u8, layout: Layout, new_size: usize) -> *mut u8 {
        let new_layout = unsafe { Layout::from_size_align_unchecked(new_size, layout.align()) };
        if !mapped(&layout) && !mapped(&new_layout) {
            return unsafe { System.realloc(ptr, layout, new_size) };
        }
        // Crossing the threshold or growing a mapped block: a new block, the old one copied and freed.
        let made = unsafe { self.alloc(new_layout) };
        if !made.is_null() {
            unsafe {
                std::ptr::copy_nonoverlapping(ptr, made, layout.size().min(new_size));
                self.dealloc(ptr, layout);
            }
        }
        made
    }
}
