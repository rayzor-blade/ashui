fn main() {
    println!("cargo:rerun-if-changed=../native/menu.m");
    if std::env::var("CARGO_CFG_TARGET_OS").as_deref() == Ok("macos") {
        cc::Build::new()
            .file("../native/menu.m")
            .flag("-fobjc-arc")
            .compile("ashui_menu");
        println!("cargo:rustc-link-lib=framework=AppKit");
    }
}
