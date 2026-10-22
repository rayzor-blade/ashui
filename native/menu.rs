//! Desktop menu bridge. Other desktops use Ashui's in-window menubar.
use hl_abi::{define_prim, vbyte};
#[cfg(target_os = "macos")]
unsafe extern "C" {
    fn ashui_menu_install(json: *const vbyte) -> bool;
    fn ashui_menu_poll() -> i32;
    fn ashui_menu_clear();
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
