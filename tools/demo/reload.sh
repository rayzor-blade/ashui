#!/bin/sh
# Opens the hot reload demo on Ash with --hot-reload and recompiles it
# whenever a .hx file under tools/demo or haxe/ changes; the window then takes
# the new code and keeps its state. Needs ../hlwgpu, ../hlwindow and a built
# ../ash checkout; the libraries are built as needed.
#   reload.sh [Demo.hx]   defaults to Reloading.hx
set -e
cd "$(dirname "$0")"
repo="$(cd ../.. && pwd)"
vib="$(cd "$repo/.." && pwd)"
demo="${1:-Reloading.hx}"
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

# Compiles beside the running .hl and moves it into place, so Ash never reads a half-written file.
build() {
	haxe --class-path "$repo/haxe" --class-path "$repo/components/haxe" --class-path "$repo/canvaskit/haxe" -lib hashlink -lib tink_hxx -w -WDeprecated \
		--class-path "$vib/hlwgpu/haxe" --class-path "$vib/hlwindow/haxe" --class-path "$vib/ash/haxelib/ash-future" --class-path "$vib/ash/haxelib/ash-simd" -D ash_simd \
		-D ashui_window -D ashui_hot_reload --macro 'ashui.core.render.UiFramework.register()' \
		--class-path . -main "$name" -hl "bin/$name.next.hl" && mv "bin/$name.next.hl" "bin/$name.hl"
}
build
touch bin/.reload-stamp

# Polls for saved sources while the window is open.
(
	while sleep 0.5; do
		if [ -n "$(find . "$repo/haxe" -name '*.hx' -newer bin/.reload-stamp 2>/dev/null | head -1)" ]; then
			touch bin/.reload-stamp
			echo "[reload.sh] rebuilding"
			build || echo "[reload.sh] build failed; the window keeps the code it has"
		fi
	done
) &
watcher=$!
trap 'kill $watcher 2>/dev/null' EXIT INT TERM
cd bin && "$vib/ash/target/release/ash" --mode "${ASH_MODE:-hybrid}" --hot-reload "$PWD/$name.hl"
