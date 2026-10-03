#!/bin/sh
# Opens the interactions demo in a window, on Ash, in its default hybrid mode;
# ASH_MODE picks another. Needs built ../hlwgpu, ../hlwindow and ../ash checkouts.
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
cargo build --release --manifest-path "$repo/Cargo.toml"
rm -f bin/blinc_abi.hdll
cp "$repo/target/release/libblinc_abi.$ext" bin/blinc_abi.hdll
rm -f bin/xgpu.hdll
cp "$(ls -t "$vib"/hlwgpu/target/*/libhlwgpu.$ext | head -1)" bin/xgpu.hdll
rm -f bin/xwindow.hdll
cp "$(ls -t "$vib"/hlwindow/target/*/libhlwindow.$ext | head -1)" bin/xwindow.hdll
haxe --class-path "$repo/haxe" -lib hashlink -lib tink_hxx -w -WDeprecated \
	--class-path "$vib/hlwgpu/haxe" --class-path "$vib/hlwindow/haxe" --class-path "$vib/ash/haxelib/ash-future" \
	-D ashui_window --macro 'ashui.core.render.UiFramework.register()' \
	--class-path . -main "$name" -hl "bin/$name.hl"
cd bin && exec "$vib/ash/target/release/ash" --mode "${ASH_MODE:-hybrid}" "$PWD/$name.hl"
