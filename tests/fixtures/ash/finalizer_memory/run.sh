#!/bin/sh
# Builds memrepro.hdll and MemRepro.hl, then runs it under $HL (default: the
# sibling ash checkout's release build). Arguments go to the runtime, e.g.
# `run.sh --mode interp`.
#   HL_INCLUDE  directory with hl.h      (default: ../../../../../ash/std)
#   HL_LIB      libhl to link against    (default: ~/.ash/bin/libhl.dylib)
set -e
cd "$(dirname "$0")"
mkdir -p bin
include="${HL_INCLUDE:-$(cd ../../../../../ash/std 2>/dev/null && pwd)}"
case "$(uname)" in
Darwin)
	lib="${HL_LIB:-$HOME/.ash/bin/libhl.dylib}"
	cc -shared -o bin/memrepro.hdll memrepro.c -I "$include" "$lib"
	install_name_tool -change "$(otool -D "$lib" | tail -1)" @rpath/libhl.dylib bin/memrepro.hdll
	;;
*)
	cc -shared -fPIC -o bin/memrepro.hdll memrepro.c -I "$include"
	;;
esac
[ -f bin/MemRepro.hl ] || haxe -main MemRepro -hl bin/MemRepro.hl
runtime="${HL:-$(cd ../../../../../ash/target/release && pwd)/ash}"
cd bin && exec "$runtime" "$@" "$PWD/MemRepro.hl"
