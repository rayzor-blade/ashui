#!/bin/sh
# Builds blinc_abi as a wasm side module and three programs, has Ash build each
# for a page, and runs them in headless Chrome: PageSmoke, a short check of what
# a page needs; ashui's whole smoke test; and WindowPage, an ashui window drawn
# by xgpu in the page's canvas, for which hlwindow and hlwgpu are built too and
# the canvas is checked for pixels.
#
#   tests/wasm/run.sh [PageSmoke|Smoke|WindowPage]
#
# Needs nightly Rust with rust-src (the side modules), Node 22 or later, Google
# Chrome (CHROME=/path/to/chrome to name one) with WebGPU, Ash 0.1.10 or later
# (ASH=/path/to/ash), and
# ImageMagick for the canvas check. Work files go to tests/bin/wasm.
#
# ASHUI_WASM_SMALL=1 builds for size, as a site would ship: blinc_abi with fat
# LTO and opt-level z, the programs with LLVM's Oz, and every module's name
# section dropped. It takes a few minutes longer and prints each module's size.
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
if [ -n "${ASHUI_WASM_SMALL:-}" ]; then
  export CARGO_PROFILE_RELEASE_LTO=fat CARGO_PROFILE_RELEASE_OPT_LEVEL=z CARGO_PROFILE_RELEASE_CODEGEN_UNITS=1 ASH_LLVM_PASSES='default<Oz>'
fi
sh ../scripts/build_wasm.sh "$out"

# Drops each module's name section in $1 and says what is left, when building small.
shrink() {
  [ -n "${ASHUI_WASM_SMALL:-}" ] || return 0
  for module in "$1"/*.wasm; do
    python3 ../scripts/strip_wasm_names.py "$module" "$module.tmp" > /dev/null && mv "$module.tmp" "$module"
    echo "wasm: $(basename "$module") $(wc -c < "$module" | tr -d ' ') bytes, $(brotli -q 9 -c "$module" 2> /dev/null | wc -c | tr -d ' ') brotli"
  done
}

free_port() { node -e 'const s = require("net").createServer().listen(0, "127.0.0.1", () => { console.log(s.address().port); s.close(); })'; }

# Serves $1 and runs its page in a Chrome of its own, for at most $2 seconds; further arguments go to run_page.mjs.
run_page() {
  dir=$1; seconds=$2
  shift 2
  port=$(free_port)
  debug=$(free_port)
  profile=$(mktemp -d)
  "$ash" serve --port "$port" "$dir" > "$dir/serve.log" 2>&1 &
  server=$!
  "$chrome" --headless=new --no-first-run --no-default-browser-check --user-data-dir="$profile" \
    --remote-debugging-port="$debug" --window-size=1280,1000 about:blank > "$dir/chrome.log" 2>&1 &
  browser=$!
  sleep 2
  code=0
  node wasm/run_page.mjs "http://127.0.0.1:$port/index.html" "$debug" "$seconds" "$@" || code=$?
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
  shrink "$dir"
  run_page "$dir" 300
}

# WindowPage: an ashui window in a page, xwindow and xgpu built from their repositories beside ashui, and its canvas checked for pixels.
window_page() {
  [ -z "$only" ] || [ "$only" = WindowPage ] || return 0
  vib=$(cd ../.. && pwd)
  if [ ! -f "$vib/hlwindow/scripts/build_wasm.sh" ] || [ ! -f "$vib/hlwgpu/scripts/build_wasm.sh" ]; then
    echo "== WindowPage: skipped, it needs hlwindow and hlwgpu checked out beside ashui"
    return 0
  fi
  echo "== WindowPage"
  dir="$out/window-page"
  mkdir -p "$dir"
  (cd "$vib/hlwindow" && sh scripts/build_wasm.sh "$here/$dir") || return 1
  # A new directory each time: hlwgpu's build script writes gpu-agent.mjs only when cargo runs it, and cargo runs it only when this path changes.
  gpu=$(mktemp -d)
  (cd "$vib/hlwgpu" && sh scripts/build_wasm.sh "$gpu") || { rm -rf "$gpu"; return 1; }
  cp "$gpu"/* "$dir/"
  rm -rf "$gpu"
  [ -f "$dir/gpu-agent.mjs" ] || { echo "wasm: hlwgpu's build wrote no gpu-agent.mjs"; return 1; }
  cp "$out/blinc_abi.wasm" "$dir/"
  $haxe_ui -D wasm -D ashui_no_hdll -D ashui_window --macro "ashui.core.render.UiFramework.register()" --macro "ashui.macro.DefaultFonts.stage()" \
    --class-path ../components/haxe --class-path ../icons/haxe --class-path ../../hlwgpu/haxe --class-path ../../ash/haxelib/ash-future \
    --class-path wasm -main WindowPage -hl "$dir/window-page.hl"
  ASH_WASM_FIBERS=1 "$ash" --build "$dir/window-page.wasm" --target wasm32-wasip1-threads "$dir/window-page.hl" > "$dir/build.log" 2>&1 || { cat "$dir/build.log"; return 1; }
  shrink "$dir"
  rm -f "$dir/window.png" "$dir/window.png.json"
  run_page "$dir" 120 --shot "$dir/window.png" --when drawing || return 1
  if ! command -v magick > /dev/null; then
    echo "wasm: no ImageMagick, so the canvas was not checked for pixels"
    return 0
  fi
  [ -f "$dir/window.png.json" ] || { echo "wasm: the page had no canvas to check"; return 1; }
  crop=$(node -e 'const r = JSON.parse(require("fs").readFileSync(process.argv[1])); console.log(`${Math.round(r.width)}x${Math.round(r.height)}+${Math.round(r.x)}+${Math.round(r.y)}`)' "$dir/window.png.json")
  colours=$(magick "$dir/window.png" -crop "$crop" +repage -format %k info:)
  # A clear colour alone is one; the icon and the text are many, anti-aliased.
  if [ "$colours" -lt 30 ]; then
    echo "wasm: FAIL: the canvas holds $colours colours; the window drew nothing"
    return 1
  fi
  echo "wasm: the canvas holds $colours colours"
}

status=0
program page-smoke PageSmoke wasm || status=$?
[ $status -ne 0 ] || program smoke Smoke . -D ashui_css=fixtures/css/smoke.css --macro 'ashui.core.Assets.embed("fixtures/assets", "embedded")' || status=$?
[ $status -ne 0 ] || window_page || status=$?
exit $status
