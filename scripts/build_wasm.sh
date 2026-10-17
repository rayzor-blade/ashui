#!/bin/sh
# Build the wasm side module blinc_abi.wasm, for a program built with Ash's
# threaded wasm target (ash --build --target wasm32-wasip1-threads).
#
#     scripts/build_wasm.sh [output directory]
#
# The same recipe as hlwgpu's and hlwindow's side modules: a position-independent
# standard library on nightly with rust-src, the threaded WASI target so the
# module shares the program's memory, and every primitive named as an export,
# since nothing inside the module calls them.
set -e

here=$(cd "$(dirname "$0")/.." && pwd)
out=${1:-"$here/target/wasm"}
mkdir -p "$out"
rm -f "$out/blinc_abi.wasm"

# --unresolved-symbols: blinc_abi also builds as a cdylib of its own, which
# imports the HashLink runtime the program supplies.
CARGO_PROFILE_RELEASE_LTO=${CARGO_PROFILE_RELEASE_LTO:-false} \
RUSTFLAGS="-C relocation-model=pic -C target-feature=+mutable-globals -C panic=abort -C link-arg=--unresolved-symbols=import-dynamic" \
  cargo +nightly rustc --manifest-path "$here/Cargo.toml" --lib --crate-type staticlib \
    --target wasm32-wasip1-threads --release \
    -Z build-std=std,panic_abort

archive="${CARGO_TARGET_DIR:-$here/target}/wasm32-wasip1-threads/release/libblinc_abi.a"
sysroot=$(rustc +nightly --print sysroot)
lld=$(find "$sysroot/lib/rustlib" -name rust-lld -type f | head -1)
nm=$(find "$sysroot/lib/rustlib" -name llvm-nm -type f | head -1)
[ -n "$lld" ] && [ -n "$nm" ] || { echo "no rust-lld or llvm-nm in the nightly sysroot" >&2; exit 1; }

# One resolver export per primitive the archive defines. The file name is
# blinc_abi.wasm because @:hlNative("blinc_abi", ...) names the library.
exports=$("$nm" --defined-only --extern-only "$archive" 2>/dev/null | sed -n 's/.* T \(hlp_[A-Za-z0-9_]*\)$/--export=\1/p' | sort -u)
[ -n "$exports" ] || { echo "no hlp_ primitives in $archive" >&2; exit 1; }

# -Bsymbolic: the module addresses its own functions and statics relative to its base,
# so no global-offset-table entry needs the loader to place it.
# shellcheck disable=SC2086
"$lld" -flavor wasm \
  --experimental-pic -shared -Bsymbolic --no-entry \
  --unresolved-symbols=import-dynamic --gc-sections --no-export-dynamic \
  --shared-memory --max-memory=1073741824 \
  $exports \
  --whole-archive "$archive" --no-whole-archive \
  -o "$out/blinc_abi.wasm"

echo "wrote $out/blinc_abi.wasm ($(wc -c < "$out/blinc_abi.wasm" | tr -d ' ') bytes)"
