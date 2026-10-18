#!/bin/sh
# Type-checks the dashboard for a desktop window, without writing anything: apps/dashboard/check.sh
set -e
here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/../.." && pwd)"
vib="$(cd "$repo/.." && pwd)"
cd "$here"
haxe --class-path "$repo/haxe" --class-path "$repo/components/haxe" --class-path "$repo/canvaskit/haxe" --class-path "$repo/media/haxe" --class-path "$repo/icons/haxe" \
	-lib hashlink -lib tink_hxx -w -WDeprecated \
	--class-path "$vib/hlwgpu/haxe" --class-path "$vib/hlwindow/haxe" --class-path "$vib/ash/haxelib/ash-future" --class-path "$vib/ash/haxelib/ash-simd" -D ash_simd \
	--class-path "$vib/hlavi/haxe" -D hlavi_no_hdll \
	-D ashui_window -D "ashui_css=$here/src/dashboard/dashboard.css" --macro 'ashui.core.render.UiFramework.register()' --macro 'ashui.ui.Markup.enable()' \
	--class-path src -main dashboard.Main -hl /dev/null --no-output
