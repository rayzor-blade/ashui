#!/bin/sh
# A cast that fails inside try must be caught. Builds Trap.hl and runs it in
# each of Ash's modes; every mode should print "caught: ..." then "after".
# $HL overrides the runtime (default: the sibling ash checkout's release build).
set -e
cd "$(dirname "$0")"
mkdir -p bin
haxe -main Trap -hl bin/Trap.hl
runtime="${HL:-$(cd ../../../../../ash/target/release && pwd)/ash}"
for mode in interp hybrid jit; do
	printf '%s: ' "$mode"
	out=$("$runtime" --mode "$mode" "$PWD/bin/Trap.hl" 2>&1 | grep -v '^\[ash\]' | grep -E 'caught|after|trap' | tr '\n' ' ') || true
	echo "$out"
done
