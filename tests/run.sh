#!/bin/sh
# Builds blinc_abi.hdll and the smoke test, then runs it under Ash (or the
# runtime named by $HL, e.g. HL=hl for stock HashLink).
set -e
cd "$(dirname "$0")"
cargo build --manifest-path ../Cargo.toml
mkdir -p bin
case "$(uname)" in
Darwin) lib=libblinc_abi.dylib ;;
*) lib=libblinc_abi.so ;;
esac
cp "../target/debug/$lib" bin/blinc_abi.hdll
haxe smoke.hxml
# Stock hl finds the hdll through its rpath entry for the current directory;
# Ash looks beside the program, so the path is absolute.
cd bin
exec "${HL:-ash}" "$PWD/smoke.hl"
