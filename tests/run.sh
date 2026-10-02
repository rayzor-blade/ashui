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
# The sibling ash checkout's release build when there is one: an installed
# ash can lag behind it.
runtime=ash
if [ -x ../../ash/target/release/ash ]; then
	runtime="$(cd ../../ash/target/release && pwd)/ash"
fi
# Stock hl finds the hdll through its rpath entry for the current directory;
# Ash looks beside the program, so the path is absolute.
cd bin
exec "${HL:-$runtime}" "$PWD/smoke.hl"
