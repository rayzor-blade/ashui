#!/bin/sh
# Renders a scene offscreen to a PNG with ashui.core.render.Snapshot, on Rayzor, as run.sh does on Ash.
# The PNG lands in .ashui/snapshots (or $ASHUI_SNAPSHOT_DIR) and each render
# or failure appends a line to events.log there.
#
#   run-rayzor.sh Scene.hx
#
# Needs, as environment variables:
#   BLINC_ABI        libblinc_abi built with --features rayzor
#   BLINC_CSS        the blinc-css tool (blinc_abi, --features css-cli)
#   RAYZOR_GPU       librayzor_gpu_plugin, built from ../rayzor/gpu/plugin with --features webgpu-backend
#                    (rebuild it whenever the rayzor runtime changes: it carries a copy of it)
# and optionally:
#   RAYZOR           the rayzor binary, default ../rayzor/target/release/rayzor
#   RAYZOR_STD_PATH  its haxe-std directory, default ../rayzor/compiler/haxe-std
#   RAYZOR_ARGS      more arguments for `rayzor run`, such as --no-cache
#   RAYZOR_EXTRA_CP  a directory searched before ashui's own sources, to try a modified copy of a module
# Needs ../hlwgpu (for hxsl) and ../hlwindow beside this repository.
#
# The scene is the same Haxe that run.sh renders. Rayzor's GPU externs are `rayzor.gpu`, which ashui imports as `gpu`,
# so a copy of them in package `gpu` is made in the build directory.
set -e
[ -n "$1" ] || { echo "usage: run-rayzor.sh Scene.hx" >&2; exit 2; }
for v in BLINC_ABI BLINC_CSS RAYZOR_GPU; do
	eval "[ -n \"\${$v}\" ]" || { echo "$v is not set" >&2; exit 2; }
done
scene="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
name="$(basename "$scene" .hx)"
scene_css="${scene%.hx}.css"

cd "$(dirname "$0")"
repo="$(cd ../.. && pwd)"
vib="$(cd "$repo/.." && pwd)"
RAYZOR="${RAYZOR:-$vib/rayzor/target/release/rayzor}"
RAYZOR_STD_PATH="${RAYZOR_STD_PATH:-$vib/rayzor/compiler/haxe-std}"
export RAYZOR_STD_PATH BLINC_CSS

ASHUI_SNAPSHOT_DIR="${ASHUI_SNAPSHOT_DIR:-$repo/.ashui/snapshots}"
export ASHUI_SNAPSHOT_DIR
mkdir -p "$ASHUI_SNAPSHOT_DIR"
events="$ASHUI_SNAPSHOT_DIR/events.log"
touch "$events"

work="$PWD/bin/rayzor-$name"
rm -rf "$work"
mkdir -p "$work/src" "$work/gpu/gpu" "$work/hxsl" "$work/home"
for f in "$vib"/rayzor/gpu/haxe/rayzor/gpu/*.hx; do
	sed 's/rayzor\.gpu/gpu/g' "$f" > "$work/gpu/gpu/$(basename "$f")"
done
# Only hlwgpu's hxsl: its own `gpu` externs would clash with the copy above.
ln -s "$vib/hlwgpu/haxe/hlwgpu" "$work/hxsl/hlwgpu"

# Only the scene is put on the class path, not its directory: the other scenes there are named like ashui's own classes.
cp "$scene" "$work/src/$name.hx"
# CompiledCss.file finds its stylesheet beside the scene.
[ -f "$scene_css" ] && cp "$scene_css" "$work/src/"
# Bitmap.embed reads relative to the build's working directory, which run.sh's builds have as this directory.
ln -s "$PWD/assets" "$work/assets"
# A run-time path such as CSS's url("../assets/x.jpg") is read from the directory run.sh runs in, `bin`, beside `assets`.
[ -e bin/assets ] || ln -s "$PWD/assets" bin/assets 2>/dev/null || true

# The core modules come before the render ones, so that the scene's own imports cannot put them in the order that breaks.
cat > "$work/src/RayzorMain.hx" <<HX
import ashui.layout.Element;
import ashui.layout.LayoutTree;
import ashui.reactive.Owner;
import ashui.ui.Div;

class RayzorMain {
	static function main() {
		$name.main();
	}
}
HX

# The hxx macro runs on tink_hxx and its dependencies, found as `-lib` finds them.
tink_cp=""
tink_defines=""
while IFS= read -r line; do
	case "$line" in
	/*) tink_cp="$tink_cp, \"${line%/}\"" ;;
	-D\ *=*) kv="${line#-D }"; tink_defines="$tink_defines
${kv%%=*} = \"${kv#*=}\"" ;;
	esac
done <<LIBS
$(haxelib path tink_hxx 2>/dev/null)
LIBS

extra_cp=""
[ -n "$RAYZOR_EXTRA_CP" ] && extra_cp="\"$RAYZOR_EXTRA_CP\", "
css_define=""
[ -f "$scene_css" ] && css_define="ashui_css = \"$scene_css\""
cat > "$work/rayzor.toml" <<TOML
[project]
name = "$name"
version = "0.1.0"
entry = "src/RayzorMain.hx"

[build]
class-paths = ["src", ${extra_cp}"$repo/haxe", "$repo/components/haxe", "$repo/canvaskit/haxe", "$repo/media/haxe", "$repo/icons/haxe", "$vib/hlwindow/haxe", "$work/gpu", "$work/hxsl"$tink_cp]
native-libs = ["$BLINC_ABI", "$RAYZOR_GPU"]
macros = ["ashui.core.render.UiFramework.register()", "ashui.ui.Markup.enable()"]

[build.defines]
ashui_rayzor = true
ashui_gpu = true$tink_defines
$css_define
TOML

cd "$work"
# Snapshot logs its own errors; this catches a crash or a failed build.
HOME="$work/home" perl -e 'alarm 900; exec @ARGV' "$RAYZOR" run ${RAYZOR_ARGS:-} src/RayzorMain.hx ||
	{ status=$?; grep -q "^error $name " "$events" 2>/dev/null || echo "error $name exited with status $status" >> "$events"; exit 1; }
