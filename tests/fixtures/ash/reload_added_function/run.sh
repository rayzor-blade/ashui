#!/bin/sh
# Hot reload with an added closure, on Ash: builds v1/Prog.hx, runs it under
# `ash --hot-reload`, rebuilds the same .hl from v2/Prog.hx (one closure
# added, of a type v1 already has, so no type or class layout changes) and
# prints what the program saw. Arguments go to ash.
set -e
cd "$(dirname "$0")"
mkdir -p bin
ash="$(cd ../../../../../ash/target/release && pwd)/ash"
build() { haxe --class-path "$1" -main Prog -hl bin/prog.hl; }
build v1
pkill -f "hot-reload $PWD/bin/prog.hl" 2>/dev/null || true
rm -f bin/prog.log
(cd bin && exec "$ash" --mode hybrid --hot-reload "$@" "$PWD/prog.hl" > prog.log 2>&1) &
pid=$!
waitfor() {
	for _ in $(seq 1 1200); do
		grep -qE "$1" bin/prog.log 2>/dev/null && return 0
		kill -0 $pid 2>/dev/null || return 1
		sleep 0.1
	done
	return 1
}
waitfor '^ready' || { cat bin/prog.log; exit 1; }
sleep 1
build v2
waitfor '^(reloaded|no reload)' || true
kill $pid 2>/dev/null || true
grep -E '^(ready|reloaded|no reload)|hot-reload\]|CRASH|rror' bin/prog.log
