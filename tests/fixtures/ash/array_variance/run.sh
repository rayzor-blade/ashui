#!/bin/sh
# An invalid array cast must throw where it happens, as stock HashLink does.
# Builds Variance.hl and runs it in each of Ash's modes; every mode should
# print "Can't cast hl.types.ArrayBytes_Float to hl.types.ArrayObj".
# $HL overrides the runtime (default: the sibling ash checkout's release build).
set -e
cd "$(dirname "$0")"
mkdir -p bin
haxe -main Variance -hl bin/Variance.hl
runtime="${HL:-$(cd ../../../../../ash/target/release && pwd)/ash}"
for mode in interp hybrid jit; do
	printf '%s: ' "$mode"
	out=$("$runtime" --mode "$mode" "$PWD/bin/Variance.hl" 2>&1 | grep -v '^\[ash\]' | grep -E "Can't cast|not cast|Null access" | head -1) || true
	echo "$out"
done
