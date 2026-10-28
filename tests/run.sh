#!/bin/sh
# Builds blinc_abi.hdll and runs the UI tests under Ash, or the runtime named
# by $HL (HL=hl for stock HashLink).
#
#   run.sh          the smoke test, the CSS parser and value tests, then the compile fixtures
#   run.sh memory   resident memory per round of allocations; prints, does not assert
#   run.sh render   draws a scene offscreen with hlwgpu and checks pixels; Ash only,
#                   needs a built ../hlwgpu checkout beside this one
#   run.sh render-caribou   the same pixel test on caribou and its GPU plugin;
#                   needs a built ../caribou and a ../blinc_abi checkout (the plugin is built from it)
#   run.sh window   opens a window with hlwindow and draws into it through a scheme
#                   switch; Ash only, needs ../hlwgpu and ../hlwindow built, and a
#                   desktop. Captures go to ../.ashui/snapshots on macOS.
set -e
# The first of the given files that exists.
first() {
	for f in "$@"; do
		[ -f "$f" ] && { echo "$f"; return; }
	done
}
cd "$(dirname "$0")"
cargo build --manifest-path ../Cargo.toml
mkdir -p bin
case "$(uname)" in
Darwin) lib=libblinc_abi.dylib ;;
*) lib=libblinc_abi.so ;;
esac
rm -f bin/blinc_abi.hdll
cp "../target/debug/$lib" bin/blinc_abi.hdll

# The sibling ash checkout's release build when there is one: an installed
# ash can lag behind it.
runtime=ash
if [ -x ../../ash/target/release/ash ]; then
	runtime="$(cd ../../ash/target/release && pwd)/ash"
fi
runtime="${HL:-$runtime}"

# tink's own sources use deprecated metadata. ASHUI_HAXE_FLAGS adds compiler flags.
haxe_ui="haxe --class-path ../haxe --class-path ../../hlwindow/haxe --class-path ../../ash/haxelib/ash-simd -D ash_simd -lib hashlink -lib tink_hxx -w -WDeprecated --macro ashui.ui.Markup.enable() ${ASHUI_HAXE_FLAGS:-}"

# The sibling libraries' release builds are used when there are any, the debug ones otherwise.
# A library copied over an older copy in place keeps a stale code signature
# on macOS, which kills the process that loads it; so copies replace files.

# Stock hl finds the hdll through its rpath entry for the current directory;
# Ash looks beside the program, so programs run from bin by absolute path.
run() {
	(cd bin && "$runtime" "$PWD/$1" "$2" "$3")
}

# Each fixtures/compile/X.hx must fail to compile with the message its first
# line names after "// expect: ".
compile_fixtures() {
	status=0
	for f in fixtures/compile/*.hx; do
		name=$(basename "$f" .hx)
		expect=$(sed -n '1s|^// expect: ||p' "$f")
		# An optional second line, "// flags: …", adds compiler flags.
		flags=$(sed -n '2s|^// flags: ||p' "$f")
		if out=$($haxe_ui --class-path fixtures/compile $flags -main "$name" -hl bin/compile.hl --no-output 2>&1); then
			echo "FAIL $name: compiled"
			status=1
		else
			case "$out" in
			*"$expect"*) echo "ok   $name" ;;
			*)
				echo "FAIL $name: expected \"$expect\", got:"
				echo "$out" | grep -v Warning | head -3
				status=1
				;;
			esac
		fi
	done
	return $status
}

# Editor requests inside inline markup: each asks the compiler at the byte just past `text` in
# fixtures/display/MarkupDisplay.hx and looks for `want` in its answer.
display_fixtures() {
	status=0
	f=fixtures/display/MarkupDisplay.hx
	ask() {
		at=$(( $(grep -boF -- "$2" "$f" | head -1 | cut -d: -f1) + ${#2} ))
		out=$($haxe_ui --class-path fixtures/display -main MarkupDisplay -hl bin/display.hl --no-output --display "$f@$at$3" 2>&1)
		case "$out" in
		*"$4"*) echo "ok   display: $1" ;;
		*)
			echo "FAIL display: $1: expected \"$4\", got:"
			echo "$out" | head -3
			status=1
			;;
		esac
	}
	ask "a field of a signal in an attribute" 'width={count.' "" 'n="get"'
	ask "a field of a loop variable" '{n.' "" 'n="charAt"'
	ask "the type of a name in a child" '<text>{co' "@type" 'Signal&lt;Int&gt;'
	ask "the definition of a name in a child" '<text>{co' "@position" 'MarkupDisplay.hx:8:'
	return $status
}

case "${1:-}" in
render)
	# hlwgpu's library, built when missing or out of date.
	cargo build --release --manifest-path ../../hlwgpu/Cargo.toml -p hlwgpu
	xgpu=$(first ../../hlwgpu/target/release/libhlwgpu.dylib ../../hlwgpu/target/release/libhlwgpu.so)
	rm -f bin/xgpu.hdll
	cp "$xgpu" bin/xgpu.hdll
	$haxe_ui --class-path ../../hlwgpu/haxe --class-path ../../ash/haxelib/ash-future \
		--macro 'ashui.core.render.UiFramework.register()' \
		--class-path ../canvaskit/haxe --class-path fixtures/render -main Pixels -hl bin/pixels.hl
	run pixels.hl
	$haxe_ui --class-path ../../hlwgpu/haxe --class-path ../../ash/haxelib/ash-future \
		--macro 'ashui.core.render.UiFramework.register()' \
		--class-path ../components/haxe --class-path fixtures/render -main TableRowSpanPixels -hl bin/table-row-span-pixels.hl
	run table-row-span-pixels.hl
	$haxe_ui --class-path ../../hlwgpu/haxe --class-path ../../ash/haxelib/ash-future \
		--macro 'ashui.core.render.UiFramework.register()' \
		--class-path ../components/haxe --class-path fixtures/render -main ComponentSizePixels -hl bin/component-size-pixels.hl
	run component-size-pixels.hl
	$haxe_ui --class-path ../../hlwgpu/haxe --class-path ../../ash/haxelib/ash-future \
		--macro 'ashui.core.render.UiFramework.register()' \
		--class-path ../canvaskit/haxe -D ashui_border_pixels -main TwBorders -hl bin/tw-border-pixels.hl
	run tw-border-pixels.hl
	$haxe_ui --class-path ../../hlwgpu/haxe --class-path ../../ash/haxelib/ash-future \
		--macro 'ashui.core.render.UiFramework.register()' \
		--class-path ../canvaskit/haxe --class-path fixtures/render -main SceneGizmoPixels -hl bin/scene-gizmo-pixels.hl
	run scene-gizmo-pixels.hl
	$haxe_ui --class-path ../../hlwgpu/haxe --class-path ../../ash/haxelib/ash-future \
		--macro 'ashui.core.render.UiFramework.register()' \
		--class-path ../canvaskit/haxe --class-path fixtures/render -main SceneSelectionPixels -hl bin/scene-selection-pixels.hl
	run scene-selection-pixels.hl
	# Text in a rounded clip that an outer clip cuts is drawn (git-bug 9dadd58).
	$haxe_ui --class-path ../../hlwgpu/haxe --class-path ../../ash/haxelib/ash-future \
		--macro 'ashui.core.render.UiFramework.register()' \
		--class-path fixtures/render -main NestedClipTextPixels -hl bin/nested-clip-text-pixels.hl
	run nested-clip-text-pixels.hl
	$haxe_ui --class-path ../../hlwgpu/haxe --class-path ../../ash/haxelib/ash-future \
		--macro 'ashui.core.render.UiFramework.register()' \
		--class-path fixtures/render -main NestedRoundedClipPixels -hl bin/nested-rounded-clip-pixels.hl
	run nested-rounded-clip-pixels.hl
	# A frame drawn as the parts of the last that changed matches the frame drawn whole (git-bug 9f040d8).
	$haxe_ui --class-path ../../hlwgpu/haxe --class-path ../../ash/haxelib/ash-future \
		--macro 'ashui.core.render.UiFramework.register()' \
		--class-path fixtures/render -main DamagePixels -hl bin/damage-pixels.hl
	run damage-pixels.hl
	# Scrolled content, icons, text and canvases drawn in parts match the whole frame (git-bug 9f040d8).
	$haxe_ui --class-path ../../hlwgpu/haxe --class-path ../../ash/haxelib/ash-future \
		--macro 'ashui.core.render.UiFramework.register()' \
		--class-path fixtures/render -main DamageScrollPixels -hl bin/damage-scroll-pixels.hl
	run damage-scroll-pixels.hl
	# Opt-in scroll images release/reload pixels and reclaim atlas capacity without changing shared images.
	$haxe_ui --class-path ../../hlwgpu/haxe --class-path ../../ash/haxelib/ash-future \
		--macro 'ashui.core.render.UiFramework.register()' \
		--class-path fixtures/render -main ImageResidencyPixels -hl bin/image-residency-pixels.hl
	run image-residency-pixels.hl
	# A rect along the axes drawn in two triangles matches the same rect drawn by the sweep (git-bug 3ec0b2c).
	$haxe_ui --class-path ../../hlwgpu/haxe --class-path ../../ash/haxelib/ash-future \
		--macro 'ashui.core.render.UiFramework.register()' \
		--class-path fixtures/render -main RectPixels -hl bin/rect-pixels.hl
	run rect-pixels.hl
	# A code editor's empty slots draw no layers, which are render passes of the window's size (git-bug 3ec0b2c).
	$haxe_ui --class-path ../../hlwgpu/haxe --class-path ../../ash/haxelib/ash-future \
		--macro 'ashui.core.render.UiFramework.register()' \
		--class-path ../components/haxe --class-path fixtures/render -main EditorLayersPixels -hl bin/editor-layers-pixels.hl
	run editor-layers-pixels.hl
	$haxe_ui --class-path ../../hlwgpu/haxe --class-path ../../ash/haxelib/ash-future \
		--macro 'ashui.core.render.UiFramework.register()' \
		--class-path ../components/haxe --class-path fixtures/render -main EditorTokenPixels -hl bin/editor-token-pixels.hl
	run editor-token-pixels.hl
	$haxe_ui --class-path ../../hlwgpu/haxe --class-path ../../ash/haxelib/ash-future \
		--macro 'ashui.core.render.UiFramework.register()' \
		--class-path ../components/haxe -main CodeMinimapLayout -hl bin/code-minimap-layout.hl
	run code-minimap-layout.hl
	# A canvas past a texture's limit draws in part, and a GPU error in a frame is a throw or a count.
	$haxe_ui --class-path ../../hlwgpu/haxe --class-path ../../ash/haxelib/ash-future \
		--macro 'ashui.core.render.UiFramework.register()' \
		--class-path fixtures/render -main GpuErrorPixels -hl bin/gpu-error-pixels.hl
	run gpu-error-pixels.hl
	;;
window)
	# hlwgpu's and hlwindow's libraries, built when missing or out of date.
	cargo build --release --manifest-path ../../hlwgpu/Cargo.toml -p hlwgpu
	cargo build --release --manifest-path ../../hlwindow/Cargo.toml
	xgpu=$(first ../../hlwgpu/target/release/libhlwgpu.dylib ../../hlwgpu/target/release/libhlwgpu.so)
	xwindow=$(first ../../hlwindow/target/release/libhlwindow.dylib ../../hlwindow/target/release/libhlwindow.so)
	rm -f bin/xgpu.hdll
	cp "$xgpu" bin/xgpu.hdll
	rm -f bin/xwindow.hdll
	cp "$xwindow" bin/xwindow.hdll
	$haxe_ui --class-path ../components/haxe --class-path ../../hlwgpu/haxe --class-path ../../ash/haxelib/ash-future \
		-D ashui_window --macro 'ashui.core.render.UiFramework.register()' \
		--class-path fixtures/window -main NumberWheelWindow -hl bin/number-wheel-window.hl
	run number-wheel-window.hl
	$haxe_ui --class-path ../../hlwgpu/haxe --class-path ../../ash/haxelib/ash-future \
		-D ashui_window --macro 'ashui.core.render.UiFramework.register()' \
		--class-path fixtures/window -main WindowDemo -hl bin/window.hl
	mkdir -p ../.ashui/snapshots
	run window.hl "$(cd ../.ashui/snapshots && pwd)"
	$haxe_ui --class-path ../../hlwgpu/haxe --class-path ../../ash/haxelib/ash-future \
		-D ashui_window --macro 'ashui.core.render.UiFramework.register()' \
		--class-path fixtures/window -main IdleWake -hl bin/idle-wake.hl
	ASHUI_WINDOW_SECONDS=8 run idle-wake.hl
	$haxe_ui --class-path ../../hlwgpu/haxe --class-path ../../ash/haxelib/ash-future \
		-D ashui_window --macro 'ashui.core.render.UiFramework.register()' \
		--class-path fixtures/window -main CanvasIdle -hl bin/canvas-idle.hl
	ASHUI_WINDOW_SECONDS=6 run canvas-idle.hl
	;;
render-caribou)
	# The pixel test on caribou's runtime and its GPU plugin, needing a built
	# ../caribou: the plugin is read at compile time to generate the gpu
	# package, so it sits in plugins/ beside the program.
	caribou="$(cd ../../caribou && pwd)"
	[ -x "$caribou/target/release/caribou" ] || { echo "no caribou build: cargo build --release in ../caribou" >&2; exit 1; }
	mkdir -p bin/caribou/plugins
	cp "$caribou/target/release/libcaribou_gpu.dylib" bin/caribou/plugins/ 2>/dev/null ||
		cp "$caribou/target/release/libcaribou_gpu.so" bin/caribou/plugins/
	cp "$caribou/target/release/libcaribou_window.dylib" bin/caribou/plugins/ 2>/dev/null ||
		cp "$caribou/target/release/libcaribou_window.so" bin/caribou/plugins/
	# blinc_abi as a caribou plugin, from its checkout (BLINC_ABI names another).
	abi="${BLINC_ABI:-../../blinc_abi}"
	[ -f "$abi/Cargo.toml" ] || { echo "no blinc_abi checkout at $abi" >&2; exit 1; }
	cargo build --release --manifest-path "$abi/Cargo.toml" --no-default-features --features caribou
	cp "$abi/target/release/libblinc_abi.dylib" bin/caribou/plugins/ 2>/dev/null ||
		cp "$abi/target/release/libblinc_abi.so" bin/caribou/plugins/
	rm -f bin/caribou/blinc_abi.hdll
	# The application menu and file dialogs, a plugin of ashui's own.
	cargo build --release --manifest-path ../desktop/Cargo.toml
	cp ../desktop/target/release/libashui_desktop.dylib bin/caribou/plugins/ 2>/dev/null ||
		cp ../desktop/target/release/libashui_desktop.so bin/caribou/plugins/
	# Caribou's own gpu and window packages, so not hlwindow's class path.
	haxe --class-path ../haxe --class-path ../../ash/haxelib/ash-simd -D ash_simd -lib hashlink -lib tink_hxx -w -WDeprecated \
		--macro 'ashui.ui.Markup.enable()' -lib caribou -D ashui_caribou --macro 'ashui.core.render.UiFramework.register()' \
		--class-path ../canvaskit/haxe --class-path fixtures/render -main Pixels -hl bin/caribou/pixels.hl
	(cd bin/caribou && "$caribou/target/release/caribou" run pixels.hl)
	# Caribou reads every file of a class path, so TwBorders sits in a directory of its own, not tests/.
	mkdir -p bin/caribou/src && cp TwBorders.hx bin/caribou/src/
	haxe --class-path ../haxe --class-path ../../ash/haxelib/ash-simd -D ash_simd -lib hashlink -lib tink_hxx -w -WDeprecated \
		--macro 'ashui.ui.Markup.enable()' -lib caribou -D ashui_caribou --macro 'ashui.core.render.UiFramework.register()' \
		--class-path ../canvaskit/haxe --class-path bin/caribou/src -D ashui_border_pixels -main TwBorders -hl bin/caribou/tw-border-pixels.hl
	(cd bin/caribou && "$caribou/target/release/caribou" run tw-border-pixels.hl)
	;;
memory)
	$haxe_ui --class-path fixtures/memory -main Memory -hl bin/memory.hl
	for kind in tree tree-dispose color signal computed; do
		run memory.hl $kind
	done
	run memory.hl signal noflush
	run memory.hl computed noflush
	;;
"")
	haxe smoke.hxml ${ASHUI_HAXE_FLAGS:-}
	smoke=0
	run smoke.hl || smoke=$?
	$haxe_ui --class-path . -main TwBorders -hl bin/tw-borders.hl
	tw_borders=0
	run tw-borders.hl || tw_borders=$?
	# Shared equal-write suppression and paused canvas ownership (f12b432, 364d4b2).
	$haxe_ui --class-path fixtures/reactive -main IdleSignalsAndCanvas -hl bin/idle-signals-canvas.hl
	idle=0
	run idle-signals-canvas.hl || idle=$?
	# Cached string-signal decode by native revision, dependency tracking kept (2059910).
	$haxe_ui --class-path fixtures/reactive -main SignalStringCache -hl bin/signal-string-cache.hl
	signal_string_cache=0
	run signal-string-cache.hl || signal_string_cache=$?
	# Quiet pointer motion, invalidation and current coordinates after coalescing.
	$haxe_ui --class-path fixtures/input -main HitCache -hl bin/hit-cache.hl
	hits=0
	run hit-cache.hl || hits=$?
	$haxe_ui --class-path fixtures/debug -main HitMapTest -hl bin/hit-map.hl
	hitmap=0
	run hit-map.hl || hitmap=$?
	$haxe_ui --class-path fixtures/css -main CssLayoutEffects -hl bin/css-layout-effects.hl
	effects=0
	run css-layout-effects.hl || effects=$?
	$haxe_ui --class-path fixtures/css -main CssLayoutBindings -hl bin/css-layout-bindings.hl
	bindings=0
	run css-layout-bindings.hl || bindings=$?
	# Global theme subscriptions survive presentation-owner disposal (2abc23a).
	$haxe_ui --class-path fixtures/css -main CssThemeOwnership -hl bin/css-theme-ownership.hl
	theme_ownership=0
	run css-theme-ownership.hl || theme_ownership=$?
	# `--ui-zoom` on :root follows the @media rules of the window's size.
	$haxe_ui --class-path fixtures/css -main CssRootZoom -hl bin/css-root-zoom.hl
	root_zoom=0
	run css-root-zoom.hl || root_zoom=$?
	# A chosen scheme holds against the window's appearance until none is chosen.
	$haxe_ui -D ashui_window --class-path fixtures/css -main WindowThemeChoice -hl bin/window-theme-choice.hl
	window_theme=0
	run window-theme-choice.hl || window_theme=$?
	# The disabled debug probe reads the environment once, not per lookup (9764792).
	$haxe_ui --class-path fixtures/css -main ThemeColorDebugProbe -hl bin/theme-color-debug-probe.hl
	theme_debug_probe=0
	run theme-color-debug-probe.hl || theme_debug_probe=$?
	$haxe_ui --class-path fixtures/css -main CssTables -hl bin/css-tables.hl
	tables=0
	run css-tables.hl || tables=$?
	$haxe_ui --class-path fixtures/css -main TableSpans -hl bin/table-spans.hl
	table_spans=0
	run table-spans.hl || table_spans=$?
	$haxe_ui --class-path fixtures/css -main TableRowSpans -hl bin/table-row-spans.hl
	row_spans=0
	run table-row-spans.hl || row_spans=$?
	$haxe_ui --class-path fixtures/css -main CssInteractionStyles -hl bin/css-interaction-styles.hl
	interaction_styles=0
	run css-interaction-styles.hl || interaction_styles=$?
	$haxe_ui --class-path ../components/haxe --class-path fixtures/input -main DialogForms -hl bin/dialog-forms.hl
	dialog_forms=0
	run dialog-forms.hl || dialog_forms=$?
	# The ashui.components library, on its own class path.
	haxe components.hxml
	components=0
	run components.hl || components=$?
	# A label whose box width came from layout rounding no longer wraps itself (743b470).
	$haxe_ui --class-path ../components/haxe --class-path fixtures/components -main TextWrapRounding -hl bin/text-wrap-rounding.hl
	text_wrap_rounding=0
	run text-wrap-rounding.hl || text_wrap_rounding=$?
	# Declarative repeated command items preserve filtering and owner cleanup (6a88875).
	$haxe_ui --class-path ../components/haxe --class-path fixtures/components -main CommandItems -hl bin/command-items.hl
	command_items=0
	run command-items.hl || command_items=$?
	# Select and Accordion take options and sections from <for> and <if> (git-bug b410c4c).
	$haxe_ui --class-path ../components/haxe --class-path fixtures/components -main ComponentFragments -hl bin/component-fragments.hl
	component_fragments=0
	run component-fragments.hl || component_fragments=$?
	# Fonts a program bundles are found by their family name (git-bug 0c8c9a0).
	$haxe_ui --class-path fixtures/text -main BundledFonts -hl bin/bundled-fonts.hl
	bundled_fonts=0
	run bundled-fonts.hl || bundled_fonts=$?
	# An IconSet class has a typed, lazily made constant per SVG file (git-bug abb6355).
	$haxe_ui --class-path fixtures/svg -main IconSets -hl bin/icon-sets.hl
	icon_sets=0
	run icon-sets.hl || icon_sets=$?
	# The Remix catalogue, and a set combining it with an app's own icons (git-bug abb6355).
	$haxe_ui --class-path ../icons/haxe --class-path fixtures/icons -main RemixCatalogue -hl bin/remix-catalogue.hl
	remix_catalogue=0
	run remix-catalogue.hl || remix_catalogue=$?
	# Command navigation reveals selection after layout and preserves manual scroll (08938d7).
	$haxe_ui --class-path ../components/haxe --class-path fixtures/components -main CommandScroll -hl bin/command-scroll.hl
	command_scroll=0
	run command-scroll.hl || command_scroll=$?
	# Shared component sizes and the editing geometry affected by CSS density (git-bug e8a1b50).
	$haxe_ui --class-path ../components/haxe --class-path fixtures/components -main ComponentSizes -hl bin/component-sizes.hl
	component_sizes=0
	run component-sizes.hl || component_sizes=$?
	# Inline knob SVGs retain switch behavior and animate without remounting (26f6deb).
	$haxe_ui --class-path ../components/haxe --class-path fixtures/components -main SwitchIcons -hl bin/switch-icons.hl
	switch_icons=0
	run switch-icons.hl || switch_icons=$?
	# A persistent Tabs background uses FLIP and retains pointer/keyboard input (5bc757e).
	$haxe_ui --class-path ../components/haxe --class-path fixtures/components -main TabsIndicator -hl bin/tabs-indicator.hl
	tabs_indicator=0
	run tabs-indicator.hl || tabs_indicator=$?
	# Native code editing, cached syntax/folds, virtual rows and owner cleanup (e53597f).
	$haxe_ui --class-path ../components/haxe --class-path fixtures/components -main CodeComponents -hl bin/code-components.hl
	code_components=0
	run code-components.hl || code_components=$?
	# Persistent document/history data without retained editor UI.
	$haxe_ui --class-path ../components/haxe --class-path fixtures/components -main CodeStateLifecycle -hl bin/code-state-lifecycle.hl
	code_state=0
	run code-state-lifecycle.hl || code_state=$?
	# Text an inline flow makes for its lines goes with the flow.
	$haxe_ui --class-path ../components/haxe --class-path fixtures/components -main InlineFlowRelease -hl bin/inline-flow-release.hl
	inline_release=0
	run inline-flow-release.hl || inline_release=$?
	# Hover/focus changes reuse CSS timing definitions without losing retiming (e1a026f).
	$haxe_ui --class-path fixtures/css -main CssTransitionReuse -hl bin/css-transition-reuse.hl
	transition_reuse=0
	run css-transition-reuse.hl || transition_reuse=$?
	# The line and word diff the diff view stands on (ed51114).
	$haxe_ui --class-path ../components/haxe --class-path fixtures/components -main CodeDiffEngine -hl bin/code-diff-engine.hl
	diff_engine=0
	run code-diff-engine.hl || diff_engine=$?
	# The rows of a diff, inline and side by side (ed51114).
	$haxe_ui --class-path ../components/haxe --class-path fixtures/components -main CodeDiffRowsCheck -hl bin/code-diff-rows.hl
	diff_rows=0
	run code-diff-rows.hl || diff_rows=$?
	# A diff's lines, coloured as rows ask for them (ed51114).
	$haxe_ui --class-path ../components/haxe --class-path fixtures/components -main CodeDiffTextCheck -hl bin/code-diff-text.hl
	diff_text=0
	run code-diff-text.hl || diff_text=$?
	# The diff view: rows by layout, placeholders, navigation, supplied changes and the worker's comparison (ed51114).
	$haxe_ui --class-path ../components/haxe --class-path fixtures/components -main CodeDiffComponent -hl bin/code-diff-component.hl
	diff_view=0
	run code-diff-component.hl || diff_view=$?
	# Zones in the editor: rows, positions, folds, edits and the minimap with an element between two lines (e23bd16).
	$haxe_ui --class-path ../components/haxe --class-path fixtures/components -main CodeZonesEditor -hl bin/code-zones-editor.hl
	code_zones_editor=0
	run code-zones-editor.hl || code_zones_editor=$?
	# Boundary markers and minimap marks of the editor's annotations (96ae277, 118ce57).
	$haxe_ui --class-path ../components/haxe --class-path fixtures/components -main CodeChangeMarks -hl bin/code-change-marks.hl
	change_marks=0
	run code-change-marks.hl || change_marks=$?
	# Compact gutters track document-wide markers and folds, independently of visible rows.
	$haxe_ui --class-path ../components/haxe --class-path fixtures/components -main CodeGutterColumns -hl bin/code-gutter-columns.hl
	gutter_columns=0
	run code-gutter-columns.hl || gutter_columns=$?
	# A dialog's panel built after the dialog, inside an if, opens with it (chimpmonk report).
	$haxe_ui --class-path ../components/haxe --class-path fixtures/components -main DialogLateContent -hl bin/dialog-late-content.hl
	dialog_late=0
	run dialog-late-content.hl || dialog_late=$?
	# A scroll container's reach and its edge shadows (bd8f627).
	$haxe_ui --class-path fixtures/css -main ScrollReach -hl bin/scroll-reach.hl
	scroll_reach=0
	run scroll-reach.hl || scroll_reach=$?
	# Rows with zones between them (e23bd16).
	$haxe_ui --class-path ../components/haxe --class-path fixtures/components -main CodeZonesCheck -hl bin/code-zones.hl
	code_zones=0
	run code-zones.hl || code_zones=$?
	# A node's field tables follow the hash maps they replace.
	$haxe_ui --class-path fixtures/css -main FieldTables -hl bin/field-tables.hl
	field_tables=0
	run field-tables.hl || field_tables=$?
	# Repeated rows share immutable CSS snapshots and allocate only requested state (0973e0c).
	$haxe_ui --class-path fixtures/css -main SharedComputedStyles -hl bin/shared-computed-styles.hl
	shared_styles=0
	run shared-computed-styles.hl || shared_styles=$?
	# Filled numeric gauges: real wheel/drag/key events, interval limits and owner cleanup (095fab4).
	$haxe_ui --class-path ../components/haxe --class-path fixtures/components -main NumberGauges -hl bin/number-gauges-test.hl
	number_gauges=0
	run number-gauges-test.hl || number_gauges=$?
	# Numeric resets supersede formatting already waiting in the reactive queue.
	$haxe_ui --class-path fixtures/input -main NumberSynchronization -hl bin/number-synchronization.hl
	number_sync=0
	run number-synchronization.hl || number_sync=$?
	# Scroll gestures retain ownership when content reveals numeric controls (095fab4).
	$haxe_ui --class-path ../components/haxe --class-path fixtures/input -main NumberWheelOwnership -hl bin/number-wheel-ownership.hl
	number_wheel=0
	run number-wheel-ownership.hl || number_wheel=$?
	# Conditional tooltips release their top-layer entries during owner teardown.
	# Descendant keyboard focus opens immediately and keeps pointer delay (8dd8f7e).
	$haxe_ui --class-path ../components/haxe --class-path fixtures/input -main TooltipFocus -hl bin/tooltip-focus.hl
	tooltip_focus=0
	run tooltip-focus.hl || tooltip_focus=$?
	$haxe_ui --class-path ../components/haxe --class-path fixtures/input -main TooltipDisposal -hl bin/tooltip-disposal.hl
	tooltip_disposal=0
	run tooltip-disposal.hl || tooltip_disposal=$?
	# A floating panel opened again while it is still closing, then closed, leaves nothing removed twice.
	$haxe_ui --class-path ../components/haxe --class-path fixtures/input -main FloatingReopen -hl bin/floating-reopen.hl
	floating_reopen=0
	run floating-reopen.hl || floating_reopen=$?
	# A ticker or timer that throws is dropped and the others in its tick still run.
	$haxe_ui --class-path fixtures/reactive -main SchedulerFailures -hl bin/scheduler-failures.hl
	scheduler_failures=0
	run scheduler-failures.hl || scheduler_failures=$?
	# Motion tracing: what each animation records and what the checks find.
	haxe motion.hxml
	motion=0
	run motion.hl || motion=$?
	# Pure Haxe, so the interpreter runs it.
	css=0
	haxe --class-path ../haxe --class-path . -main CssValues --interp || css=$?
	# ashui.draw's vector core: flattening and the triangles of fills and strokes.
	haxe --class-path ../haxe --class-path . -main Draw --interp || css=$?
	compile=0
	compile_fixtures || compile=$?
	display=0
	display_fixtures || display=$?
	# Only -D ashui_window compiles the window's own code: a build of it that does not compile must not pass the suite.
	windowed=0
	$haxe_ui --class-path ../../hlwgpu/haxe --class-path ../../ash/haxelib/ash-future \
		-D ashui_window --macro 'ashui.core.render.UiFramework.register()' \
		--class-path fixtures/window -main WindowDemo -hl bin/window-compile.hl --no-output || windowed=$?
	[ $smoke -eq 0 ] && [ $tw_borders -eq 0 ] && [ $idle -eq 0 ] && [ $signal_string_cache -eq 0 ] && [ $hits -eq 0 ] && [ $hitmap -eq 0 ] && [ $effects -eq 0 ] && [ $bindings -eq 0 ] && [ $theme_ownership -eq 0 ] && [ $root_zoom -eq 0 ] && [ $window_theme -eq 0 ] && [ $theme_debug_probe -eq 0 ] && [ $tables -eq 0 ] && [ $table_spans -eq 0 ] && [ $row_spans -eq 0 ] && [ $interaction_styles -eq 0 ] && [ $dialog_forms -eq 0 ] && [ $components -eq 0 ] && [ $text_wrap_rounding -eq 0 ] && [ $command_items -eq 0 ] && [ $component_fragments -eq 0 ] && [ $bundled_fonts -eq 0 ] && [ $icon_sets -eq 0 ] && [ $remix_catalogue -eq 0 ] && [ $command_scroll -eq 0 ] && [ $component_sizes -eq 0 ] && [ $switch_icons -eq 0 ] && [ $tabs_indicator -eq 0 ] && [ $code_components -eq 0 ] && [ $code_state -eq 0 ] && [ $inline_release -eq 0 ] && [ $transition_reuse -eq 0 ] && [ $field_tables -eq 0 ] && [ $code_zones -eq 0 ] && [ $scroll_reach -eq 0 ] && [ $code_zones_editor -eq 0 ] && [ $change_marks -eq 0 ] && [ $dialog_late -eq 0 ] && [ $gutter_columns -eq 0 ] && [ $diff_engine -eq 0 ] && [ $diff_rows -eq 0 ] && [ $diff_text -eq 0 ] && [ $diff_view -eq 0 ] && [ $shared_styles -eq 0 ] && [ $number_gauges -eq 0 ] && [ $number_sync -eq 0 ] && [ $number_wheel -eq 0 ] && [ $tooltip_focus -eq 0 ] && [ $tooltip_disposal -eq 0 ] && [ $floating_reopen -eq 0 ] && [ $scheduler_failures -eq 0 ] && [ $motion -eq 0 ] && [ $css -eq 0 ] && [ $compile -eq 0 ] && [ $display -eq 0 ] && [ $windowed -eq 0 ]
	;;
*)
	echo "usage: run.sh [memory|render|render-caribou|window]" >&2
	exit 2
	;;
esac
