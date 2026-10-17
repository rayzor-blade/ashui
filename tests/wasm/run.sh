#!/bin/sh
# Builds blinc_abi as a wasm side module and a small program, has Ash build the
# program for a page, and runs it in headless Chrome.
#
#   tests/wasm/run.sh
#
# Needs nightly Rust with rust-src (the side module), Node 22 or later, Google
# Chrome (CHROME=/path/to/chrome to name one), and an Ash with libm in its
# wasm runtime (ASH=/path/to/ash). Work files go to tests/bin/wasm.
set -e
cd "$(dirname "$0")/.."
here=$(pwd)
ash=${ASH:-$(command -v "$here/../../ash/target/release/ash" || command -v ash || true)}
[ -x "$ash" ] || { echo "wasm: no ash; set ASH" >&2; exit 1; }
chrome=${CHROME:-"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"}
[ -x "$chrome" ] || { echo "wasm: no Chrome at $chrome; set CHROME" >&2; exit 1; }
haxe_ui="haxe --class-path ../haxe --class-path ../../hlwindow/haxe --class-path ../../ash/haxelib/ash-simd -D ash_simd -lib hashlink -lib tink_hxx -w -WDeprecated --macro ashui.ui.Markup.enable()"

out=bin/wasm
rm -rf "$out"
mkdir -p "$out"
sh ../scripts/build_wasm.sh "$out"
# NativeInstall copies the desktop library beside the bytecode; a page has the .wasm instead.
$haxe_ui -D ashui_no_hdll --class-path wasm -main PageSmoke -hl "$out/page-smoke.hl"
ASH_WASM_FIBERS=1 "$ash" --build "$out/page-smoke.wasm" --target wasm32-wasip1-threads "$out/page-smoke.hl"

free_port() { node -e 'const s = require("net").createServer().listen(0, "127.0.0.1", () => { console.log(s.address().port); s.close(); })'; }
port=$(free_port)
debug=$(free_port)
profile=$(mktemp -d)
"$ash" serve --port "$port" "$out" > "$out/serve.log" 2>&1 &
server=$!
"$chrome" --headless=new --no-first-run --no-default-browser-check --user-data-dir="$profile" \
  --remote-debugging-port="$debug" --window-size=1280,1000 about:blank > "$out/chrome.log" 2>&1 &
browser=$!
# The status is the page's; stopping the browser and clearing its profile must not change it.
cleanup() {
  code=$?
  kill $server $browser 2>/dev/null || true
  wait $server $browser 2>/dev/null || true
  rm -rf "$profile" 2>/dev/null || true
  exit $code
}
trap cleanup EXIT INT TERM
sleep 2
status=0
node wasm/run_page.mjs "http://127.0.0.1:$port/index.html" "$debug" 120 || status=$?
exit $status
