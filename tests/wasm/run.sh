#!/bin/sh
# Builds blinc_abi as a wasm side module and two programs, has Ash build each
# for a page, and runs them in headless Chrome: PageSmoke, a short check of what
# a page needs, and ashui's whole smoke test.
#
#   tests/wasm/run.sh [PageSmoke|Smoke]
#
# Needs nightly Rust with rust-src (the side module), Node 22 or later, Google
# Chrome (CHROME=/path/to/chrome to name one), and an Ash with libm and the
# side-module loader fixes in its wasm runtime (ASH=/path/to/ash). Work files go
# to tests/bin/wasm.
set -e
cd "$(dirname "$0")/.."
here=$(pwd)
ash=${ASH:-$(command -v "$here/../../ash/target/release/ash" || command -v ash || true)}
[ -x "$ash" ] || { echo "wasm: no ash; set ASH" >&2; exit 1; }
chrome=${CHROME:-"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"}
[ -x "$chrome" ] || { echo "wasm: no Chrome at $chrome; set CHROME" >&2; exit 1; }
haxe_ui="haxe --class-path ../haxe --class-path ../../hlwindow/haxe --class-path ../../ash/haxelib/ash-simd -D ash_simd -lib hashlink -lib tink_hxx -w -WDeprecated --macro ashui.ui.Markup.enable()"
only=${1:-}

out=bin/wasm
rm -rf "$out"
mkdir -p "$out"
sh ../scripts/build_wasm.sh "$out"

free_port() { node -e 'const s = require("net").createServer().listen(0, "127.0.0.1", () => { console.log(s.address().port); s.close(); })'; }

# Serves $1 and runs its page in a Chrome of its own, for at most $2 seconds.
run_page() {
  port=$(free_port)
  debug=$(free_port)
  profile=$(mktemp -d)
  "$ash" serve --port "$port" "$1" > "$1/serve.log" 2>&1 &
  server=$!
  "$chrome" --headless=new --no-first-run --no-default-browser-check --user-data-dir="$profile" \
    --remote-debugging-port="$debug" --window-size=1280,1000 about:blank > "$1/chrome.log" 2>&1 &
  browser=$!
  sleep 2
  code=0
  node wasm/run_page.mjs "http://127.0.0.1:$port/index.html" "$debug" "$2" || code=$?
  kill $server $browser 2>/dev/null || true
  wait $server $browser 2>/dev/null || true
  rm -rf "$profile" 2>/dev/null || true
  return $code
}

# program <name> <main class> <class path> [haxe flags]: compiles it as a web build, builds it for a page and runs it.
program() {
  name=$1; main=$2; path=$3
  shift 3
  [ -z "$only" ] || [ "$only" = "$main" ] || return 0
  echo "== $main"
  dir="$out/$name"
  mkdir -p "$dir"
  cp "$out/blinc_abi.wasm" "$dir/"
  # NativeInstall copies the desktop library beside the bytecode; a page has the .wasm instead.
  $haxe_ui -D wasm -D ashui_no_hdll --macro "ashui.macro.DefaultFonts.stage()" --class-path "$path" "$@" -main "$main" -hl "$dir/$name.hl"
  ASH_WASM_FIBERS=1 "$ash" --build "$dir/$name.wasm" --target wasm32-wasip1-threads "$dir/$name.hl" > "$dir/build.log" 2>&1 || { cat "$dir/build.log"; return 1; }
  run_page "$dir" 300
}

status=0
program page-smoke PageSmoke wasm || status=$?
[ $status -ne 0 ] || program smoke Smoke . -D ashui_css=fixtures/css/smoke.css || status=$?
exit $status
