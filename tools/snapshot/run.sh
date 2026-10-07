#!/bin/sh
# Renders a scene offscreen to a PNG with ashui.core.render.Snapshot, on Ash.
# The PNG lands in .ashui/snapshots (or $ASHUI_SNAPSHOT_DIR) and each render
# or failure appends a line to events.log there, for a watcher to tail.
#
#   run.sh Scene.hx           render once
#   run.sh --watch Scene.hx   render again whenever the scene, ashui's Haxe
#                             or blinc_abi's Rust changes
#   ASH=path run.sh ...       run on that ash binary rather than ../ash's
#                             release build
#   run.sh --window Scene.hx  open the scene in a window instead, live; a
#                             motion scene plays its scripted input first.
#                             ASHUI_MOTION=overlay draws the motion overlay.
#
# A scene is a class whose main calls Snapshot.scene; see scenes/Demo.hx.
# A .css file beside the scene is declared for HXX's class checking and watched too.
# Needs ../hlwgpu (and ../hlwindow for --window) beside this repository, built here as needed, and a built ../ash.
set -e
watch=0
window=0
while :; do
	case "$1" in
	--watch) watch=1; shift ;;
	--window) window=1; shift ;;
	*) break ;;
	esac
done
[ -n "$1" ] || { echo "usage: run.sh [--watch] [--window] Scene.hx" >&2; exit 2; }
scene="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
name="$(basename "$scene" .hx)"
scene_css="${scene%.hx}.css"
css="$scene_css"
[ -f "$css" ] || css=""

cd "$(dirname "$0")"
repo="$(cd ../.. && pwd)"
vib="$(cd "$repo/.." && pwd)"
ash="${ASH:-$vib/ash/target/release/ash}"

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
	# hlwgpu's and, for a window, hlwindow's libraries, built when missing or out of date.
	if ! out=$(cargo build --release --manifest-path "$vib/hlwgpu/Cargo.toml" -p hlwgpu 2>&1); then
		echo "error $name hlwgpu failed to build: $(echo "$out" | grep -m1 '^error')" >> "$events"
		echo "$out" >&2
		return 1
	fi
	rm -f bin/xgpu.hdll
	cp "$vib/hlwgpu/target/release/libhlwgpu.$ext" bin/xgpu.hdll
	# Media snapshots also pump a hidden native window's event loop, so native
	# opening and seeking complete before their offscreen frames are captured.
	defines=""
	if [ $window -eq 1 ] || [ "${ASHUI_MEDIA:-0}" = 1 ] || grep -q 'ashui\.media' "$scene"; then
		if ! out=$(cargo build --release --manifest-path "$vib/hlwindow/Cargo.toml" 2>&1); then
			echo "error $name hlwindow failed to build: $(echo "$out" | grep -m1 '^error')" >> "$events"
			echo "$out" >&2
			return 1
		fi
		rm -f bin/xwindow.hdll
		cp "$vib/hlwindow/target/release/libhlwindow.$ext" bin/xwindow.hdll
		if [ $window -eq 1 ]; then defines="-D ashui_window"; fi
	fi
	media_args=""
	if [ "${ASHUI_MEDIA:-0}" = 1 ] || grep -q 'ashui\.media' "$scene"; then
		if [ -z "${HLAVI_HDLL:-}" ]; then
			if ! out=$(cargo build --release --manifest-path "$vib/hlavi/Cargo.toml" 2>&1); then
				echo "error $name hlavi failed to build" >> "$events"
				echo "$out" >&2
				return 1
			fi
			media_hdll="$vib/hlavi/target/release/libhlavi.$ext"
		else
			media_hdll="$HLAVI_HDLL"
		fi
		media_args="--macro hlavi.macro.NativeInstall.stage()"
	fi
	if ! out=$(haxe --class-path "$repo/haxe" --class-path "$repo/components/haxe" --class-path "$repo/canvaskit/haxe" --class-path "$repo/media/haxe" -lib hashlink -lib tink_hxx -w -WDeprecated \
		--class-path "$vib/hlwgpu/haxe" --class-path "$vib/hlwindow/haxe" --class-path "$vib/ash/haxelib/ash-future" --class-path "$vib/ash/haxelib/ash-simd" -D ash_simd \
		--class-path "$vib/hlavi/haxe" -D "hlavi_hdll=${media_hdll:-}" $media_args \
		--macro 'ashui.core.render.UiFramework.register()' --macro 'ashui.ui.Markup.enable()' -D "ashui_css=$css" $defines \
		--class-path "$(dirname "$scene")" -main "$name" -hl "bin/$name.hl" 2>&1); then
		echo "error $name does not compile: $(echo "$out" | grep -v Warning | head -1)" >> "$events"
		echo "$out" >&2
		return 1
	fi
	# A window stays open until it is closed.
	if [ $window -eq 1 ]; then
		(cd bin && ASHUI_WINDOW=1 "$ash" "$PWD/$name.hl")
		return
	fi
	# Snapshot logs its own errors; this catches a crash or hang.
	(cd bin && perl -e 'alarm 120; exec @ARGV' "$ash" "$PWD/$name.hl") ||
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
	if [ -n "$(find "$scene" "$scene_css" "$repo/haxe" "$repo/components" "$repo/canvaskit" "$repo/media" "$repo/blinc_abi/src" -newer "$stamp" \( -name '*.hx' -o -name '*.css' -o -name '*.rs' \) 2>/dev/null | head -1)" ]; then
		touch "$stamp"
		render || true
	fi
done
