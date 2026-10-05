#!/bin/sh
# Builds blinc_abi.hdll and runs the UI tests under Ash, or the runtime named
# by $HL (HL=hl for stock HashLink).
#
#   run.sh          the smoke test, the CSS parser and value tests, then the compile fixtures
#   run.sh memory   resident memory per round of allocations; prints, does not assert
#   run.sh render   draws a scene offscreen with hlwgpu and checks pixels; Ash only,
#                   needs a built ../hlwgpu checkout beside this one
#   run.sh render-caribou   the same pixel test on caribou and its GPU plugin;
#                   needs a built ../caribou
#   run.sh window   opens a window with hlwindow and draws into it through a scheme
#                   switch; Ash only, needs ../hlwgpu and ../hlwindow built, and a
#                   desktop. Captures go to ../.ashui/snapshots on macOS.
set -e
# The first of the given files that exists.
first() {
	for f in "$@"; do
		[ -f "$f" ] && { echo "$f"; return; }
	done
}
cd "$(dirname "$0")"
cargo build --manifest-path ../Cargo.toml
mkdir -p bin
case "$(uname)" in
Darwin) lib=libblinc_abi.dylib ;;
*) lib=libblinc_abi.so ;;
esac
rm -f bin/blinc_abi.hdll
cp "../target/debug/$lib" bin/blinc_abi.hdll

# The sibling ash checkout's release build when there is one: an installed
# ash can lag behind it.
runtime=ash
if [ -x ../../ash/target/release/ash ]; then
	runtime="$(cd ../../ash/target/release && pwd)/ash"
fi
runtime="${HL:-$runtime}"

# tink's own sources use deprecated metadata.
haxe_ui="haxe --class-path ../haxe --class-path ../../hlwindow/haxe --class-path ../../ash/haxelib/ash-simd -D ash_simd -lib hashlink -lib tink_hxx -w -WDeprecated --macro ashui.ui.Markup.enable()"

# The sibling libraries' release builds are used when there are any, the debug ones otherwise.
# A library copied over an older copy in place keeps a stale code signature
# on macOS, which kills the process that loads it; so copies replace files.

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
		# An optional second line, "// flags: …", adds compiler flags.
		flags=$(sed -n '2s|^// flags: ||p' "$f")
		if out=$($haxe_ui --class-path fixtures/compile $flags -main "$name" -hl bin/compile.hl --no-output 2>&1); then
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
render)
	# hlwgpu's library, built when missing or out of date.
	cargo build --release --manifest-path ../../hlwgpu/Cargo.toml -p hlwgpu
	xgpu=$(first ../../hlwgpu/target/release/libhlwgpu.dylib ../../hlwgpu/target/release/libhlwgpu.so)
	rm -f bin/xgpu.hdll
	cp "$xgpu" bin/xgpu.hdll
	$haxe_ui --class-path ../../hlwgpu/haxe --class-path ../../ash/haxelib/ash-future \
		--macro 'ashui.core.render.UiFramework.register()' \
		--class-path ../canvaskit/haxe --class-path fixtures/render -main Pixels -hl bin/pixels.hl
	run pixels.hl
	;;
window)
	# hlwgpu's and hlwindow's libraries, built when missing or out of date.
	cargo build --release --manifest-path ../../hlwgpu/Cargo.toml -p hlwgpu
	cargo build --release --manifest-path ../../hlwindow/Cargo.toml
	xgpu=$(first ../../hlwgpu/target/release/libhlwgpu.dylib ../../hlwgpu/target/release/libhlwgpu.so)
	xwindow=$(first ../../hlwindow/target/release/libhlwindow.dylib ../../hlwindow/target/release/libhlwindow.so)
	rm -f bin/xgpu.hdll
	cp "$xgpu" bin/xgpu.hdll
	rm -f bin/xwindow.hdll
	cp "$xwindow" bin/xwindow.hdll
	$haxe_ui --class-path ../../hlwgpu/haxe --class-path ../../ash/haxelib/ash-future \
		-D ashui_window --macro 'ashui.core.render.UiFramework.register()' \
		--class-path fixtures/window -main WindowDemo -hl bin/window.hl
	mkdir -p ../.ashui/snapshots
	run window.hl "$(cd ../.ashui/snapshots && pwd)"
	;;
render-caribou)
	# The pixel test on caribou's runtime and its GPU plugin, needing a built
	# ../caribou: the plugin is read at compile time to generate the gpu
	# package, so it sits in plugins/ beside the program.
	caribou="$(cd ../../caribou && pwd)"
	[ -x "$caribou/target/release/caribou" ] || { echo "no caribou build: cargo build --release in ../caribou" >&2; exit 1; }
	mkdir -p bin/caribou/plugins
	cp "$caribou/target/release/libcaribou_gpu.dylib" bin/caribou/plugins/ 2>/dev/null ||
		cp "$caribou/target/release/libcaribou_gpu.so" bin/caribou/plugins/
	cp bin/blinc_abi.hdll bin/caribou/
	$haxe_ui -lib caribou -D ashui_caribou --macro 'ashui.core.render.UiFramework.register()' \
		--class-path fixtures/render -main Pixels -hl bin/caribou/pixels.hl
	(cd bin/caribou && "$caribou/target/release/caribou" run pixels.hl)
	;;
memory)
	$haxe_ui --class-path fixtures/memory -main Memory -hl bin/memory.hl
	for kind in tree tree-dispose color signal computed; do
		run memory.hl $kind
	done
	run memory.hl signal noflush
	run memory.hl computed noflush
	;;
"")
	haxe smoke.hxml
	smoke=0
	run smoke.hl || smoke=$?
	# The ashui.components library, on its own class path.
	haxe components.hxml
	components=0
	run components.hl || components=$?
	# Motion tracing: what each animation records and what the checks find.
	haxe motion.hxml
	motion=0
	run motion.hl || motion=$?
	# Pure Haxe, so the interpreter runs it.
	css=0
	haxe --class-path ../haxe --class-path . -main CssParse --interp || css=$?
	haxe --class-path ../haxe --class-path . -main CssValues --interp || css=$?
	# ashui.draw's vector core: flattening and the triangles of fills and strokes.
	haxe --class-path ../haxe --class-path . -main Draw --interp || css=$?
	compile=0
	compile_fixtures || compile=$?
	[ $smoke -eq 0 ] && [ $components -eq 0 ] && [ $motion -eq 0 ] && [ $css -eq 0 ] && [ $compile -eq 0 ]
	;;
*)
	echo "usage: run.sh [memory|render|render-caribou|window]" >&2
	exit 2
	;;
esac
