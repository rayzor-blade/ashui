#!/bin/sh
# Renders a page of the dashboard to .ashui/snapshots/dashboard-<page>.png, to look at while it is designed:
#
#   TAB=Media SCHEME=light apps/dashboard/preview.sh      WIDTH and HEIGHT set its size, 1600 by 820 by default
set -e
here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/../.." && pwd)"
ASHUI_HAXE_FLAGS="--macro ashui.core.Assets.embed(\"$repo/tools/snapshot/assets/3d/Mazda6\",\"assets/3d/Mazda6\") --macro ashui.core.Assets.embed(\"$repo/tools/snapshot/assets/map\",\"assets/map\") --macro ashui.core.Assets.embed(\"$here/levels\",\"assets/levels\") ${ASHUI_HAXE_FLAGS:-}" \
	exec sh "$repo/tools/snapshot/run.sh" "$here/src/Preview.hx"
