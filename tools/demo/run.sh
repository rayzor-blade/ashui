#!/bin/sh
# Opens the interactions demo in a window, on Ash, in its default hybrid mode;
# ASH_MODE picks another. Needs ../hlwgpu, ../hlwindow and a built ../ash checkout; the libraries are built as needed.
#   run.sh [Demo.hx]   defaults to Interactions.hx
# Accepts a filename in tools/demo, a path relative to the caller, or an absolute path.
# A .css file beside the demo is declared for HXX's class checking.
set -e
runner="$(cd "$(dirname "$0")" && pwd)"
demo="${1:-$runner/Interactions.hx}"
if [ ! -f "$demo" ]; then
	if [ -f "$runner/$demo" ]; then
		demo="$runner/$demo"
	else
		echo "error: demo not found: $demo" >&2
		exit 2
	fi
fi
# Resolve before changing directory, so a repo-relative path keeps its meaning.
demo="$(cd "$(dirname "$demo")" && pwd)/$(basename "$demo")"
cd "$runner"
repo="$(cd ../.. && pwd)"
vib="$(cd "$repo/.." && pwd)"
name="$(basename "$demo" .hx)"
css="${demo%.hx}.css"
[ -f "$css" ] || css=""
case "$(uname)" in
Darwin) ext=dylib ;;
*) ext=so ;;
esac
mkdir -p bin
# ashui's, hlwgpu's and hlwindow's libraries, built when missing or out of date.
cargo build --release --manifest-path "$repo/Cargo.toml"
cargo build --release --manifest-path "$vib/hlwgpu/Cargo.toml" -p hlwgpu
cargo build --release --manifest-path "$vib/hlwindow/Cargo.toml"
rm -f bin/blinc_abi.hdll
cp "$repo/target/release/libblinc_abi.$ext" bin/blinc_abi.hdll
rm -f bin/xgpu.hdll
cp "$vib/hlwgpu/target/release/libhlwgpu.$ext" bin/xgpu.hdll
rm -f bin/xwindow.hdll
cp "$vib/hlwindow/target/release/libhlwindow.$ext" bin/xwindow.hdll
# Media stays optional. Imported media tags opt a demo in; ASHUI_MEDIA=1 also
# enables demos that reach them through another module. HLAVI_HDLL uses an
# existing local or packaged binary, otherwise build the sibling checkout.
media_args=""
if [ "${ASHUI_MEDIA:-0}" = 1 ] || grep -q 'ashui\.media' "$demo"; then
	if [ -z "${HLAVI_HDLL:-}" ]; then
		cargo build --release --manifest-path "$vib/hlavi/Cargo.toml"
		HLAVI_HDLL="$vib/hlavi/target/release/libhlavi.$ext"
	fi
	media_args="--macro hlavi.macro.NativeInstall.stage()"
fi
haxe --class-path "$repo/haxe" --class-path "$repo/components/haxe" --class-path "$repo/canvaskit/haxe" --class-path "$repo/media/haxe" -lib hashlink -lib tink_hxx -w -WDeprecated \
	--class-path "$vib/hlwgpu/haxe" --class-path "$vib/hlwindow/haxe" --class-path "$vib/ash/haxelib/ash-future" --class-path "$vib/ash/haxelib/ash-simd" -D ash_simd \
	--class-path "$vib/hlavi/haxe" -D "hlavi_hdll=${HLAVI_HDLL:-}" $media_args \
	-D ashui_window -D "ashui_css=$css" --macro 'ashui.core.render.UiFramework.register()' --macro 'ashui.ui.Markup.enable()' \
	--class-path "$(dirname "$demo")" -main "$name" -hl "bin/$name.hl"
cd bin && exec "$vib/ash/target/release/ash" --mode "${ASH_MODE:-hybrid}" "$PWD/$name.hl"
