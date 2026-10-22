//! Desktop menu bridge. Other desktops use Ashui's in-window menubar.
use hl_abi::{define_prim, vbyte};
#[cfg(target_os = "macos")]
unsafe extern "C" {
    fn ashui_menu_install(json: *const vbyte) -> bool;
    fn ashui_menu_poll() -> i32;
    fn ashui_menu_clear();
    fn ashui_dialog_open(json: *const vbyte) -> bool;
    fn ashui_dialog_poll() -> i32;
    fn ashui_dialog_take(id: i32) -> *const vbyte;
    fn ashui_dialog_cancel(id: i32);
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn ui_menu_install(json: *const vbyte) -> bool {
    #[cfg(target_os = "macos")]
    return unsafe { ashui_menu_install(json) };
    #[cfg(not(target_os = "macos"))]
    { let _ = json; false }
}
define_prim!(hlp_ui_menu_install, ui_menu_install, "PB_b");
#[unsafe(no_mangle)]
pub extern "C" fn ui_menu_poll() -> i32 {
    #[cfg(target_os = "macos")]
    return unsafe { ashui_menu_poll() };
    #[cfg(not(target_os = "macos"))]
    0
}
define_prim!(hlp_ui_menu_poll, ui_menu_poll, "P_i");
#[unsafe(no_mangle)]
pub extern "C" fn ui_menu_clear() {
    #[cfg(target_os = "macos")]
    unsafe { ashui_menu_clear() };
}
define_prim!(hlp_ui_menu_clear, ui_menu_clear, "P_v");

#[unsafe(no_mangle)]
pub unsafe extern "C" fn ui_dialog_open(json: *const vbyte) -> bool {
    #[cfg(target_os = "macos")]
    return unsafe { ashui_dialog_open(json) };
    #[cfg(not(target_os = "macos"))]
    { let _ = json; false }
}
define_prim!(hlp_ui_dialog_open, ui_dialog_open, "PB_b");
#[unsafe(no_mangle)]
pub extern "C" fn ui_dialog_poll() -> i32 {
    #[cfg(target_os = "macos")]
    return unsafe { ashui_dialog_poll() };
    #[cfg(not(target_os = "macos"))]
    0
}
define_prim!(hlp_ui_dialog_poll, ui_dialog_poll, "P_i");
#[unsafe(no_mangle)]
pub unsafe extern "C" fn ui_dialog_take(id: i32) -> *mut vbyte {
    #[cfg(target_os = "macos")]
    unsafe {
        let data = ashui_dialog_take(id);
        if data.is_null() { return std::ptr::null_mut(); }
        let text = std::ffi::CStr::from_ptr(data.cast()).to_bytes_with_nul();
        let Ok(size) = i32::try_from(text.len()) else { return std::ptr::null_mut(); };
        let bytes = hl_abi::hl_alloc_bytes(size);
        if !bytes.is_null() { std::ptr::copy_nonoverlapping(text.as_ptr(), bytes, text.len()); }
        bytes
    }
    #[cfg(not(target_os = "macos"))]
    { let _ = id; std::ptr::null_mut() }
}
define_prim!(hlp_ui_dialog_take, ui_dialog_take, "Pi_B");
#[unsafe(no_mangle)]
pub extern "C" fn ui_dialog_cancel(id: i32) {
    #[cfg(target_os = "macos")]
    unsafe { ashui_dialog_cancel(id) };
    #[cfg(not(target_os = "macos"))]
    let _ = id;
}
define_prim!(hlp_ui_dialog_cancel, ui_dialog_cancel, "Pi_v");
