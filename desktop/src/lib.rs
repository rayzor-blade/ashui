//! The application menu and native file dialogs as a Caribou plugin, `Desktop`: the same functions
//! the HashLink library exports (`native/menu.rs`), over the same Objective-C. Other desktops use
//! Ashui's in-window menubar, and these report nothing.

use caribou_abi::host::{self, Text};
#[cfg(target_os = "macos")]
use std::ffi::{CStr, CString, c_char};

#[cfg(target_os = "macos")]
unsafe extern "C" {
    fn ashui_menu_install(json: *const c_char) -> bool;
    fn ashui_menu_poll() -> i32;
    fn ashui_menu_clear();
    fn ashui_dialog_open(json: *const c_char) -> bool;
    fn ashui_dialog_poll() -> i32;
    fn ashui_dialog_take(id: i32) -> *const c_char;
    fn ashui_dialog_cancel(id: i32);
}

#[cfg(target_os = "macos")]
fn c_string(t: Text) -> Option<CString> {
    CString::new(t.as_str()).ok()
}

pub struct Desktop;

impl Desktop {
    /// Installs the application menu from `json`; false where there is none to install.
    pub extern "C" fn menu_install(json: Text) -> bool {
        #[cfg(target_os = "macos")]
        if let Some(json) = c_string(json) {
            return unsafe { ashui_menu_install(json.as_ptr()) };
        }
        let _ = json;
        false
    }

    /// The id of a chosen menu item, or 0 when none was chosen.
    pub extern "C" fn menu_poll() -> i32 {
        #[cfg(target_os = "macos")]
        return unsafe { ashui_menu_poll() };
        #[cfg(not(target_os = "macos"))]
        0
    }

    pub extern "C" fn menu_clear() {
        #[cfg(target_os = "macos")]
        unsafe {
            ashui_menu_clear()
        };
    }

    /// Opens a file or folder selection described by `json`; false where there is none.
    pub extern "C" fn dialog_open(json: Text) -> bool {
        #[cfg(target_os = "macos")]
        if let Some(json) = c_string(json) {
            return unsafe { ashui_dialog_open(json.as_ptr()) };
        }
        let _ = json;
        false
    }

    /// The id of a finished dialog, or 0 when none finished.
    pub extern "C" fn dialog_poll() -> i32 {
        #[cfg(target_os = "macos")]
        return unsafe { ashui_dialog_poll() };
        #[cfg(not(target_os = "macos"))]
        0
    }

    /// The path a finished dialog chose, empty when it was cancelled.
    pub extern "C" fn dialog_take(id: i32) -> Text {
        #[cfg(target_os = "macos")]
        {
            let data = unsafe { ashui_dialog_take(id) };
            if !data.is_null() {
                let path = unsafe { CStr::from_ptr(data) }.to_string_lossy();
                return host::text(&path);
            }
        }
        let _ = id;
        host::text("")
    }

    pub extern "C" fn dialog_cancel(id: i32) {
        #[cfg(target_os = "macos")]
        unsafe {
            ashui_dialog_cancel(id)
        };
        let _ = id;
    }
}

caribou_abi::plugin! {
    name: "ashui_desktop";
    class Desktop {
        fn menu_install(Text) -> bool;
        fn menu_poll() -> i32;
        fn menu_clear();
        fn dialog_open(Text) -> bool;
        fn dialog_poll() -> i32;
        fn dialog_take(i32) -> Text;
        fn dialog_cancel(i32);
    }
}
