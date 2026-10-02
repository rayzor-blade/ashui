//! Links the HDLL against the HashLink runtime that loads it.
//!
//! On macOS the runtime's symbols must bind to `@rpath/libhl.dylib` by name:
//! Mach-O records which image each import comes from, and an executable that
//! also exports `hl_*` (Ash does) would otherwise satisfy them from a second
//! copy of the runtime. Stock HashLink and Ash both install `libhl` under that
//! name, so linking against a text stub carrying it needs neither at build
//! time and loads under either. ELF resolves the imports at load time, so
//! nothing is linked there.

use std::{env, fs, path::PathBuf};

/// Every runtime symbol `src/hl.rs` imports.
const SYMBOLS: &[&str] = &[
    "_hl_add_root",
    "_hl_alloc_bytes",
    "_hl_dyn_call",
    "_hl_gc_alloc_gen",
    "_hl_remove_root",
    "_hlt_abstract",
];

fn main() {
    println!("cargo:rerun-if-changed=build.rs");
    if env::var("CARGO_CFG_TARGET_OS").as_deref() != Ok("macos") {
        return;
    }
    let out = PathBuf::from(env::var("OUT_DIR").unwrap());
    let targets = "[ arm64-macos, x86_64-macos ]";
    let stub = format!(
        "--- !tapi-tbd\ntbd-version: 4\ntargets: {targets}\n\
         install-name: '@rpath/libhl.dylib'\n\
         exports:\n  - targets: {targets}\n    symbols: [ {} ]\n...\n",
        SYMBOLS.join(", ")
    );
    fs::write(out.join("libhl.tbd"), stub).unwrap();
    println!("cargo:rustc-link-search=native={}", out.display());
    println!("cargo:rustc-link-lib=dylib=hl");
}
