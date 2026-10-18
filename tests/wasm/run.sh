#!/bin/sh
# Builds a demo for a page, serves it and opens it in a browser. It runs no tests;
# smoke.sh does.
#
#   tests/wasm/run.sh [Dashboard|Banner|WindowPage] [--port N] [--no-open] [--rebuild]
#
# The default is Banner, the README's dashboard. BROWSER="Google Chrome" names the
# browser to open on macOS, which needs WebGPU: Chrome, Edge or a recent Safari.
# The page is served with the headers a threaded module needs, until Ctrl-C.
# --rebuild builds blinc_abi, hlwindow's and hlwgpu's web builds again; they are
# kept in tests/bin/web between runs, with each demo beside them.
#
# Needs nightly Rust with rust-src (the side modules, the first time), Ash
# (ASH=/path/to/ash) and hlwindow and hlwgpu checked out beside ashui.
set -e
cd "$(dirname "$0")/.."
out=bin/web
. wasm/lib.sh

demo=Banner
port=8123
open=1
rebuild=0
while [ $# -gt 0 ]; do
  case "$1" in
    --port) port=$2; shift ;;
    --no-open) open=0 ;;
    --rebuild) rebuild=1 ;;
    -h | --help) sed -n '2,13p' wasm/run.sh | sed 's/^# \{0,1\}//'; exit 0 ;;
    Dashboard | Banner | WindowPage) demo=$1 ;;
    *) echo "run.sh: unknown demo or option $1" >&2; exit 2 ;;
  esac
  shift
done

[ $rebuild -eq 0 ] || rm -rf "$out/blinc_abi.wasm" "$out/hlwindow-web" "$out/hlwgpu-web" "$out/web-libraries.stamp"
[ -f "$out/blinc_abi.wasm" ] || build_abi
case "$demo" in
  Dashboard) build_dashboard; dir=$out/dashboard ;;
  Banner) build_banner; dir=$out/banner ;;
  WindowPage) build_window_page; dir=$out/window-page ;;
esac

url="http://127.0.0.1:$port/"
echo "run: $demo at $url (Ctrl-C stops)"
if [ $open -eq 1 ]; then
  (
    sleep 1
    case "$(uname)" in
      Darwin) if [ -n "${BROWSER:-}" ]; then open -a "$BROWSER" "$url"; else open "$url"; fi ;;
      *) "${BROWSER:-xdg-open}" "$url" ;;
    esac
  ) &
fi
exec "$ash" serve --port "$port" "$dir"
