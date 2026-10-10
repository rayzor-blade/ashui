#!/bin/sh
# Opens the ashui debugger on a recording, on Ash's application preset.
#   run.sh [recording dir]   defaults to the newest under .ashui/snapshots/motion
# Needs ../hlwgpu, ../hlwindow and a built ../ash checkout, as tools/demo does;
# the libraries are built as needed.
set -e
here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/.." && pwd)"
vib="$(cd "$repo/.." && pwd)"
# A relative recording path keeps its meaning from where it was run.
arg=""
if [ $# -gt 0 ]; then arg="$(cd "$1" && pwd)"; fi
case "$(uname)" in
Darwin) ext=dylib ;;
*) ext=so ;;
esac
mkdir -p "$here/bin"
cargo build --release --manifest-path "$repo/Cargo.toml"
cargo build --release --manifest-path "$vib/hlwgpu/Cargo.toml" -p hlwgpu
cargo build --release --manifest-path "$vib/hlwindow/Cargo.toml"
cp "$repo/target/release/libblinc_abi.$ext" "$here/bin/blinc_abi.hdll"
cp "$vib/hlwgpu/target/release/libhlwgpu.$ext" "$here/bin/xgpu.hdll"
cp "$vib/hlwindow/target/release/libhlwindow.$ext" "$here/bin/xwindow.hdll"
cd "$here"
haxe build.hxml
# Recordings are found from the repository root, where MotionRecorder writes them.
cd "$repo"
exec "$vib/ash/target/release/ash" --mode "${ASH_MODE:-hybrid}" --preset application "$here/bin/debugger.hl" $arg
