#!/bin/sh
# Writes the block-compressed texture files for a glTF model's images, beside them: see BcPack.hx.
#
#   tools/bcpack/run.sh path/to/model.gltf [--max 2048] [--only color,data]
#
# Needs a built ../ash. blinc_abi is built here as needed; there is no GPU involved.
set -e
here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/../.." && pwd)"
vib="$(cd "$repo/.." && pwd)"
ash="${ASH:-$vib/ash/target/release/ash}"
case "$(uname)" in
Darwin) ext=dylib ;;
*) ext=so ;;
esac
[ -n "$1" ] || { echo "usage: run.sh model.gltf [--max 2048] [--only color,data]" >&2; exit 2; }
model="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
shift
cargo build --release --manifest-path "$repo/Cargo.toml" > /dev/null
mkdir -p "$here/bin"
rm -f "$here/bin/blinc_abi.hdll"
cp "$repo/target/release/libblinc_abi.$ext" "$here/bin/blinc_abi.hdll"
haxe --class-path "$repo/haxe" --class-path "$vib/ash/haxelib/ash-simd" -D ash_simd -lib hashlink -w -WDeprecated --class-path "$here" -main BcPack -hl "$here/bin/bcpack.hl"
(cd "$here/bin" && "$ash" "$PWD/bcpack.hl" "$model" "$@")
