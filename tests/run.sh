#!/bin/sh
# Builds blinc_abi.hdll and runs the UI tests under Ash, or the runtime named
# by $HL (HL=hl for stock HashLink).
#
#   run.sh          the smoke test, then the compile fixtures
#   run.sh memory   resident memory per round of allocations; prints, does not assert
set -e
cd "$(dirname "$0")"
cargo build --manifest-path ../Cargo.toml
mkdir -p bin
case "$(uname)" in
Darwin) lib=libblinc_abi.dylib ;;
*) lib=libblinc_abi.so ;;
esac
cp "../target/debug/$lib" bin/blinc_abi.hdll

# The sibling ash checkout's release build when there is one: an installed
# ash can lag behind it.
runtime=ash
if [ -x ../../ash/target/release/ash ]; then
	runtime="$(cd ../../ash/target/release && pwd)/ash"
fi
runtime="${HL:-$runtime}"

# tink's own sources use deprecated metadata.
haxe_ui="haxe --class-path ../haxe -lib hashlink -lib tink_hxx -w -WDeprecated"

# Stock hl finds the hdll through its rpath entry for the current directory;
# Ash looks beside the program, so programs run from bin by absolute path.
run() {
	(cd bin && "$runtime" "$PWD/$1" "$2" "$3")
}

# Each fixtures/compile/X.hx must fail to compile with the message its first
# line names after "// expect: ".
compile_fixtures() {
	status=0
	for f in fixtures/compile/*.hx; do
		name=$(basename "$f" .hx)
		expect=$(sed -n '1s|^// expect: ||p' "$f")
		if out=$($haxe_ui --class-path fixtures/compile -main "$name" -hl bin/compile.hl --no-output 2>&1); then
			echo "FAIL $name: compiled"
			status=1
		else
			case "$out" in
			*"$expect"*) echo "ok   $name" ;;
			*)
				echo "FAIL $name: expected \"$expect\", got:"
				echo "$out" | grep -v Warning | head -3
				status=1
				;;
			esac
		fi
	done
	return $status
}

case "${1:-}" in
memory)
	$haxe_ui --class-path fixtures/memory -main Memory -hl bin/memory.hl
	for kind in tree color signal computed; do
		run memory.hl $kind
	done
	run memory.hl signal noflush
	run memory.hl computed noflush
	;;
"")
	haxe smoke.hxml
	smoke=0
	run smoke.hl || smoke=$?
	compile=0
	compile_fixtures || compile=$?
	[ $smoke -eq 0 ] && [ $compile -eq 0 ]
	;;
*)
	echo "usage: run.sh [memory]" >&2
	exit 2
	;;
esac
