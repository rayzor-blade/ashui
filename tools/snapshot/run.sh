#!/bin/sh
# Renders a scene offscreen to a PNG with ashui.core.render.Snapshot, on Ash.
# The PNG lands in .ashui/snapshots (or $ASHUI_SNAPSHOT_DIR) and each render
# or failure appends a line to events.log there, for a watcher to tail.
#
#   run.sh Scene.hx           render once
#   run.sh --watch Scene.hx   render again whenever the scene, ashui's Haxe
#                             or blinc_abi's Rust changes
#
# A scene is a class whose main calls Snapshot.scene; see scenes/Demo.hx.
# Needs built ../ash and ../hlwgpu checkouts beside this repository.
set -e
# The first of the given files that exists.
first() {
	for f in "$@"; do
		[ -f "$f" ] && { echo "$f"; return; }
	done
}
watch=0
if [ "$1" = "--watch" ]; then
	watch=1
	shift
fi
[ -n "$1" ] || { echo "usage: run.sh [--watch] Scene.hx" >&2; exit 2; }
scene="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
name="$(basename "$scene" .hx)"

cd "$(dirname "$0")"
repo="$(cd ../.. && pwd)"
vib="$(cd "$repo/.." && pwd)"

ASHUI_SNAPSHOT_DIR="${ASHUI_SNAPSHOT_DIR:-$repo/.ashui/snapshots}"
export ASHUI_SNAPSHOT_DIR
mkdir -p "$ASHUI_SNAPSHOT_DIR" bin
events="$ASHUI_SNAPSHOT_DIR/events.log"
touch "$events"

case "$(uname)" in
Darwin) ext=dylib ;;
*) ext=so ;;
esac

render() {
	if ! out=$(cargo build --release --manifest-path "$repo/Cargo.toml" 2>&1); then
		echo "error $name blinc_abi failed to build: $(echo "$out" | grep -m1 '^error')" >> "$events"
		echo "$out" >&2
		return 1
	fi
	rm -f bin/blinc_abi.hdll
	cp "$repo/target/release/libblinc_abi.$ext" bin/blinc_abi.hdll
	rm -f bin/xgpu.hdll
	cp "$(first "$vib"/hlwgpu/target/release/libhlwgpu.$ext "$vib"/hlwgpu/target/debug/libhlwgpu.$ext)" bin/xgpu.hdll
	if ! out=$(haxe --class-path "$repo/haxe" -lib hashlink -lib tink_hxx -w -WDeprecated \
		--class-path "$vib/hlwgpu/haxe" --class-path "$vib/hlwindow/haxe" --class-path "$vib/ash/haxelib/ash-future" \
		--macro 'ashui.core.render.UiFramework.register()' \
		--class-path "$(dirname "$scene")" -main "$name" -hl "bin/$name.hl" 2>&1); then
		echo "error $name does not compile: $(echo "$out" | grep -v Warning | head -1)" >> "$events"
		echo "$out" >&2
		return 1
	fi
	# Snapshot logs its own errors; this catches a crash or hang.
	(cd bin && perl -e 'alarm 120; exec @ARGV' "$vib/ash/target/release/ash" "$PWD/$name.hl") ||
		{ status=$?; grep -q "^error $name " "$events" 2>/dev/null || echo "error $name exited with status $status" >> "$events"; return 1; }
}

if [ $watch -eq 0 ]; then
	render
	exit
fi

stamp="bin/.$name.stamp"
touch "$stamp"
render || true
echo "watching $scene; Ctrl-C stops" >&2
while sleep 0.5; do
	if [ -n "$(find "$scene" "$repo/haxe" "$repo/blinc_abi/src" -newer "$stamp" \( -name '*.hx' -o -name '*.rs' \) 2>/dev/null | head -1)" ]; then
		touch "$stamp"
		render || true
	fi
done
