#!/bin/sh
# Opens Ash Drive in a window, on Ash's application preset in hybrid mode; ASH_MODE picks another.
# Needs ../../../hlwgpu, ../../../hlwindow and ../../../hlavi checkouts and a built ../../../ash; the libraries are built as needed.
#   apps/dashboard/run.sh
# The window follows the system's light or dark appearance; the Profile page can pin one.
set -e
here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/../.." && pwd)"
vib="$(cd "$repo/.." && pwd)"
case "$(uname)" in
Darwin) ext=dylib ;;
*) ext=so ;;
esac
cd "$here"
mkdir -p bin
printf '[ashui] Native dependency: blinc_abi\n'
cargo build --release --manifest-path "$repo/Cargo.toml"
printf '[ashui] Native dependency: hlwgpu\n'
cargo build --release --manifest-path "$vib/hlwgpu/Cargo.toml" -p hlwgpu
printf '[ashui] Native dependency: hlwindow\n'
cargo build --release --manifest-path "$vib/hlwindow/Cargo.toml"
printf '[ashui] Native dependency: hlavi\n'
cargo build --release --manifest-path "$vib/hlavi/Cargo.toml"
rm -f bin/blinc_abi.hdll bin/xgpu.hdll bin/xwindow.hdll
cp "$repo/target/release/libblinc_abi.$ext" bin/blinc_abi.hdll
cp "$vib/hlwgpu/target/release/libhlwgpu.$ext" bin/xgpu.hdll
cp "$vib/hlwindow/target/release/libhlwindow.$ext" bin/xwindow.hdll
printf '[ashui] Compiling Ash Drive\n'
haxe --class-path "$repo/haxe" --class-path "$repo/components/haxe" --class-path "$repo/canvaskit/haxe" --class-path "$repo/media/haxe" --class-path "$repo/icons/haxe" \
	-lib hashlink -lib tink_hxx -w -WDeprecated \
	--class-path "$vib/hlwgpu/haxe" --class-path "$vib/hlwindow/haxe" --class-path "$vib/ash/haxelib/ash-future" --class-path "$vib/ash/haxelib/ash-simd" -D ash_simd \
	--class-path "$vib/hlavi/haxe" -D "hlavi_hdll=$vib/hlavi/target/release/libhlavi.$ext" --macro 'hlavi.macro.NativeInstall.stage()' \
	--macro "ashui.core.Assets.embed(\"$repo/tools/snapshot/assets/3d/Mazda6\", \"assets/3d/Mazda6\")" \
	--macro "ashui.core.Assets.embed(\"$repo/tools/snapshot/assets/map\", \"assets/map\")" \
	--macro "ashui.core.Assets.embed(\"$here/levels\", \"assets/levels\")" \
	-D ashui_window -D "ashui_css=$here/src/dashboard/dashboard.css" --macro 'ashui.core.render.UiFramework.register()' --macro 'ashui.ui.Markup.enable()' \
	--class-path src -main dashboard.Main -hl bin/dashboard.hl
printf '[ashui] Launching Ash Drive\n'
# From the app's folder, where the music is.
exec "$vib/ash/target/release/ash" --mode "${ASH_MODE:-hybrid}" --preset application "$here/bin/dashboard.hl"
