#!/bin/sh
# Under Ash's hybrid mode, signals partway through ashui's smoke test stop
# taking writes: a set is followed by a get of the old value, and a computed
# reading them never changes. interp and jit pass the same build. Builds the
# smoke test and runs it in each mode; every mode should print "ALL PASSED".
# $HL overrides the runtime (default: the sibling ash checkout's release build).
set -e
cd "$(dirname "$0")/../../.."
root="$(cd .. && pwd)"
mkdir -p bin
cargo build --manifest-path "$root/Cargo.toml" >/dev/null 2>&1
cp "$root/target/debug/libblinc_abi.dylib" bin/blinc_abi.hdll 2>/dev/null || cp "$root/target/debug/libblinc_abi.so" bin/blinc_abi.hdll
haxe smoke.hxml >/dev/null
runtime="${HL:-$(cd ../../ash/target/release && pwd)/ash}"
for mode in interp hybrid jit; do
	printf '%s: ' "$mode"
	(cd bin && "$runtime" --mode "$mode" smoke.hl 2>&1 | grep -E '^FAIL|ALL PASSED|FAILED' | tr '\n' ' ') || true
	echo
done
