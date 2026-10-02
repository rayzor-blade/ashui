#!/bin/sh
# Builds futrepro.hdll and FutRepro.hl, then runs it under $HL (default: the
# sibling ash checkout's release build) with each of a few delays, 10s each:
# once with the future functions linked from libhl, once found by dlsym on
# the process the way hlwgpu finds them.
# Arguments go to the runtime, e.g. `run.sh --mode jit`.
#   HL_INCLUDE  directory with hl.h      (default: ../../../../../ash/std)
#   HL_LIB      libhl to link against    (default: the sibling ash's release libhl)
set -e
cd "$(dirname "$0")"
mkdir -p bin
ash_dir="$(cd ../../../../../ash && pwd)"
include="${HL_INCLUDE:-$ash_dir/std}"
case "$(uname)" in
Darwin)
	lib="${HL_LIB:-$ash_dir/target/release/libhl.dylib}"
	cc -shared -o bin/futrepro.hdll futrepro.c -I "$include" "$lib"
	install_name_tool -change "$(otool -D "$lib" | tail -1)" @rpath/libhl.dylib bin/futrepro.hdll
	;;
*)
	cc -shared -fPIC -o bin/futrepro.hdll futrepro.c -I "$include" -lpthread
	;;
esac
haxe -main FutRepro --class-path "$ash_dir/haxelib/ash-future" -hl bin/FutRepro.hl
runtime="${HL:-$ash_dir/target/release/ash}"
cd bin
for how in linked lookup; do
for delay in 0 1000 50000; do
	printf '%-7s delay %6sus: ' "$how" "$delay"
	if out=$(perl -e 'alarm 10; exec @ARGV' "$runtime" "$@" "$PWD/FutRepro.hl" "$delay" 20 boxed "$how" 2>&1 | grep -v '^\[ash\]' | tr '\n' ' '); then :; fi
	case "$out" in
	*"resolved 20"*) echo "ok" ;;
	*) echo "HANG after: ${out:-nothing}" ;;
	esac
done
done
