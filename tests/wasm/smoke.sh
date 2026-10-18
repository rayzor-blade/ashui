#!/bin/sh
# Builds blinc_abi as a wasm side module and four programs, has Ash build each
# for a page, and runs them in headless Chrome: PageSmoke, a short check of what
# a page needs; ashui's whole smoke test; WindowPage, an ashui window drawn by
# xgpu in the page's canvas, for which hlwindow and hlwgpu are built too and the
# canvas is checked for pixels; and Banner, the README's dashboard, which has
# to keep running and drawing for the length of the run. The windows are built
# as an app is: ashui's page and the libraries' web builds come from their macros.
#
#   tests/wasm/smoke.sh [PageSmoke|Smoke|MediaPage|WindowPage|Banner]
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
chrome=${CHROME:-"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"}
[ -x "$chrome" ] || { echo "wasm: no Chrome at $chrome; set CHROME" >&2; exit 1; }
only=${1:-}

out=bin/wasm
. wasm/lib.sh
rm -rf "$out"
mkdir -p "$out"
build_abi

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
    --remote-debugging-port="$debug" --window-size=1280,1000 ${CHROME_FLAGS:-} about:blank > "$dir/chrome.log" 2>&1 &
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

# window_program <name> <main class> <seconds> <build function suffix>: builds an ashui window for a page as an app
# would be, runs it in headless Chrome and checks its canvas for pixels. A program that keeps running until the time is up passes
# (RUNNING=1); one that ends does not.
window_program() {
  name=$1; main=$2; seconds=$3
  [ -z "$only" ] || [ "$only" = "$main" ] || return 0
  echo "== $main"
  build_$4 || return 1
  dir="$out/$name"
  rm -f "$dir/window.png" "$dir/window.png.json"
  # A window says so when its first frame is on the GPU; a program that quits by itself is checked to the end instead.
  run_page "$dir" "$seconds" --shot "$dir/window.png" --when "ashui: ready|drawing" --wait "${SHOT_WAIT:-0.5}" ${RUNNING:+--running} || return 1
  if ! command -v magick > /dev/null; then
    echo "wasm: no ImageMagick, so the canvas was not checked for pixels"
    return 0
  fi
  [ -f "$dir/window.png.json" ] || { echo "wasm: the page had no canvas to check"; return 1; }
  crop=$(node -e 'const r = JSON.parse(require("fs").readFileSync(process.argv[1])); console.log(`${Math.round(r.width)}x${Math.round(r.height)}+${Math.round(r.x)}+${Math.round(r.y)}`)' "$dir/window.png.json")
  colours=$(magick "$dir/window.png" -crop "$crop" +repage -format %k info:)
  # A clear colour alone is one; text, icons and shaded surfaces are many, anti-aliased.
  if [ "$colours" -lt "${MIN_COLOURS:-30}" ]; then
    echo "wasm: FAIL: the canvas holds $colours colours; the window drew nothing"
    return 1
  fi
  echo "wasm: the canvas holds $colours colours"
}

window_page() {
  window_program window-page WindowPage 120 window_page
}

# Banner keeps running and drawing for the length of the run.
banner_page() {
  RUNNING=1 SHOT_WAIT=4 MIN_COLOURS=2000 window_program banner Banner 25 banner
}

# MediaPage: hlavi's media player in a page, on a two-second tone beside it. Headless Chrome is told it may play without a press, as
# the program has no user; the agent's wait for one is tested apart (xavi's page_agent test).
media_page() {
  [ -z "$only" ] || [ "$only" = "MediaPage" ] || return 0
  echo "== MediaPage"
  web_media || return 1
  dir="$out/media-page"
  mkdir -p "$dir"
  python3 -c '
import math, struct, sys, wave
w = wave.open(sys.argv[1], "wb")
w.setnchannels(1); w.setsampwidth(2); w.setframerate(22050)
w.writeframes(b"".join(struct.pack("<h", int(8000 * math.sin(2 * math.pi * 440 * i / 22050))) for i in range(44100)))
' "$dir/tone.wav"
  $haxe_ui -D wasm -D ashui_no_hdll -D "hlavi_web=$here/$out/hlavi-web" --macro "hlavi.macro.NativeInstall.stage()" \
    --class-path ../../hlavi/haxe --class-path ../../ash/haxelib/ash-future --class-path wasm -main MediaPage -hl "$dir/media-page.hl"
  ASH_WASM_FIBERS=1 "$ash" --build "$dir/media-page.wasm" --target wasm32-wasip1-threads "$dir/media-page.hl" > "$dir/build.log" 2>&1 || { cat "$dir/build.log"; return 1; }
  CHROME_FLAGS="--autoplay-policy=no-user-gesture-required" run_page "$dir" 120
}

status=0
program page-smoke PageSmoke wasm || status=$?
[ $status -ne 0 ] || program smoke Smoke . -D ashui_css=fixtures/css/smoke.css --macro 'ashui.core.Assets.embed("fixtures/assets", "embedded")' || status=$?
[ $status -ne 0 ] || media_page || status=$?
[ $status -ne 0 ] || window_page || status=$?
[ $status -ne 0 ] || banner_page || status=$?
exit $status
