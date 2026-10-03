#!/bin/sh
# Hot reload end to end on Ash: builds Main with v1/Panel.hx, runs it under
# `ash --hot-reload`, rebuilds the same .hl with another Panel while it runs,
# and prints what the program saw before and after the reload.
#
#   run.sh [panel-dir] [ash flags...]   panel-dir defaults to v2
#
#   v2  body-only template edit: the panel renders the new code, state kept
#   v3  adds a reactive attribute, so a new function: not a body-only change
#   v4  body-only, but the string literals change length
set -e
cd "$(dirname "$0")"
next="${1:-v2}"
[ $# -gt 0 ] && shift
root=../../..
(cd $root && cargo build -q)
mkdir -p bin
case "$(uname)" in
Darwin) lib=libblinc_abi.dylib ;;
*) lib=libblinc_abi.so ;;
esac
cp "$root/target/debug/$lib" bin/blinc_abi.hdll
ash="$(cd $root/../ash/target/release && pwd)/ash"

build() {
	haxe --class-path $root/haxe --class-path $root/../hlwindow/haxe --class-path . --class-path "$1" -lib hashlink -lib tink_hxx -w -WDeprecated -main Main -hl bin/hot.hl
}

build v1
# A run left behind by an interrupted one would poll the same file.
pkill -f "hot-reload $PWD/bin/hot.hl" 2>/dev/null || true
rm -f bin/hot.log
(cd bin && exec "$ash" --mode hybrid --hot-reload "$@" "$PWD/hot.hl" > hot.log 2>&1) &
pid=$!
# A reload that recompiles the whole program can take most of a minute.
waitfor() {
	for _ in $(seq 1 1200); do
		grep -qE "$1" bin/hot.log 2>/dev/null && return 0
		kill -0 $pid 2>/dev/null || return 1
		sleep 0.1
	done
	return 1
}
waitfor '^ready' || { cat bin/hot.log; exit 1; }
# The reload is detected by the file's modification time.
sleep 1
build "$next"
waitfor '^(reloaded|no reload)' || true
kill $pid 2>/dev/null || true
grep -E '^(ready|reloaded|no reload)|hot-reload\]|rror|CRASH' bin/hot.log
