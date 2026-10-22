#!/usr/bin/env bash
set -euo pipefail
if [ "$(uname -s)" != Darwin ]; then echo "native menu: macOS only"; exit 0; fi
root=$(cd "$(dirname "$0")/.." && pwd)
output=$(mktemp -d)
trap 'rm -rf "$output"' EXIT
clang -fobjc-arc -framework AppKit -Wl,-export_dynamic "$root/native/menu.m" "$root/tests/native-menu.m" -o "$output/check"
"$output/check"
