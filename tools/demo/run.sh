#!/bin/sh
# Opens the interactions demo in a window, on Ash, in its default hybrid mode;
# ASH_MODE picks another. Needs ../hlwgpu, ../hlwindow and a built ../ash checkout; the libraries are built as needed.
#   run.sh [Demo.hx]   defaults to Interactions.hx
set -e
cd "$(dirname "$0")"
repo="$(cd ../.. && pwd)"
vib="$(cd "$repo/.." && pwd)"
demo="${1:-Interactions.hx}"
name="$(basename "$demo" .hx)"
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
haxe --class-path "$repo/haxe" --class-path "$repo/components/haxe" --class-path "$repo/canvaskit/haxe" -lib hashlink -lib tink_hxx -w -WDeprecated \
	--class-path "$vib/hlwgpu/haxe" --class-path "$vib/hlwindow/haxe" --class-path "$vib/ash/haxelib/ash-future" --class-path "$vib/ash/haxelib/ash-simd" -D ash_simd \
	-D ashui_window --macro 'ashui.core.render.UiFramework.register()' --macro 'ashui.ui.Markup.enable()' \
	--class-path . -main "$name" -hl "bin/$name.hl"
cd bin && exec "$vib/ash/target/release/ash" --mode "${ASH_MODE:-hybrid}" "$PWD/$name.hl"
