#!/bin/bash
# Runs the Rayzor tests here. Needs, as environment variables:
#   RAYZOR           the rayzor binary
#   RAYZOR_STD_PATH  its haxe-std directory
#   BLINC_ABI        libblinc_abi built with --features rayzor
#   BLINC_CSS        the blinc-css tool (blinc_abi, --features css-cli)
# The hlwindow checkout is expected beside this one.
set -e
for v in RAYZOR RAYZOR_STD_PATH BLINC_ABI BLINC_CSS; do
	[ -n "${!v}" ] || { echo "$v is not set" >&2; exit 2; }
done
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/src" "$work/home"
cp "$here/Computeds.hx" "$work/src/Main.hx"
sed -i.bak 's/^class Computeds /class Main /' "$work/src/Main.hx"
cat > "$work/rayzor.toml" <<TOML
[project]
name = "ashui-rayzor-tests"
version = "0.1.0"
entry = "src/Main.hx"

[build]
class-paths = ["src", "$root/haxe", "$root/../hlwindow/haxe"]
native-libs = ["$BLINC_ABI"]

[build.defines]
ashui_rayzor = true
TOML
export RAYZOR_STD_PATH BLINC_CSS
cd "$work"
out=$(HOME="$work/home" "$RAYZOR" run --no-cache src/Main.hx 2>&1) || true
echo "$out" | grep -E '^(ok|FAIL|EXCEPTION|ALL PASSED|FAILED)' || true
echo "$out" | grep -q '^ALL PASSED'
