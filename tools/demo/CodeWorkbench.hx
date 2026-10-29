import ashui.components.Badge;
import ashui.components.Button;
import ashui.components.CodeEditor;
import ashui.components.CodeView;
import ashui.components.Tabs;
import ashui.css.CompiledCss;
import ashui.css.Css;
import ashui.layout.Element;
import ashui.reactive.Reactive;
import ashui.theme.themes.DefaultTheme;
import ashui.types.Style.Display;
import ashui.ui.Ref;
import ashui.reactive.Watch;
import ashui.svg.SvgDocument;
#if ashui_window
import ashui.app.WindowConfig;
import ashui.app.WindowedApp;
#else
import ashui.core.render.Snapshot;
import ashui.theme.ThemeState;
#end

/** Editable HXX, a read-only JSON preview, and existing controls (e53597f). **/
class CodeWorkbench {
	public static inline var WIDTH = 1120;
	public static inline var HEIGHT = 780;
	static var styled = false;
	public static final SAMPLE = 'import ashui.app.WindowedApp;\nimport ashui.components.Button;\nimport ashui.reactive.Reactive;\n\nclass Counter {\n    static function main() {\n        // Signals connect state to the reactive graph.\n        var count = signal(0);\n        var title = computed(() -> "Count: " + count.get());\n\n        WindowedApp.run({\n            title: "A little counter",\n            width: 420,\n            height: 280\n        }, () -> {\n            return <div class="p-6 flex-col gap-4">\n                <text>$' + '{title}</text>\n                <button onClick={_ -> count.set(count.get() + 1)}>\n                    Add one\n                </button>\n            </div>;\n        });\n    }\n}\n';
	public static function page():Element {
		if (!styled) { Css.add(CompiledCss.file("CodeWorkbench.css")); styled = true; }
		var value = signal(SAMPLE), changes = signal(0), tab = signal("source"), activity = signal("");
		var editor = new Ref<CodeEditor>();
		var actions:Array<ashui.components.code.CodeAnnotations.CodeLineActions> = [{line:5, actions:[
			{label:"Run", icon:SvgDocument.of(<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linejoin="round"><path d="m8 5 11 7-11 7z" /></svg>), run:() -> activity.set("Run requested")},
			{label:"Debug", run:() -> activity.set("Debug requested")}
		]}];
		new Watch(() -> editor.get(), view -> if (view != null) {
			view.onGutterClick = (line, _) -> {
				var existing = view.markerLinesOf("debugger");
				view.markers("debugger", existing.indexOf(line) >= 0 ? [] : [{line:line,className:"ui-code-marker-breakpoint"}], true);
			};
		});
		return <div class="cw-page" width={WIDTH} height={HEIGHT}>
			<div class="cw-header">
				<div class="flex-col gap-2"><text class="cw-eyebrow">ASHUI / COMPONENTS</text><text class="cw-title">A place for your code.</text></div>
				<badge variant={Secondary} appearance={Outline}>Native text · HXX</badge>
			</div>
			<text class="cw-description">Syntax that stays readable. Editing that feels familiar.</text>
			<div class="cw-workspace">
				<div class="cw-editor-panel">
					<div class="cw-toolbar">
						<tabs value={tab}><tabs-list><tabs-trigger value="source">Counter.hx</tabs-trigger><tabs-trigger value="notes">Notes</tabs-trigger></tabs-list></tabs>
						<div class="grow" />
						<button type="button" variant={Ghost} size={Sm} onClick={_ -> { value.set(SAMPLE); changes.set(0); activity.set(""); }}>Reset</button>
					</div>
					<!-- Retain editor history, folds and shaped rows across tab changes (2aca664). -->
					<code-editor ref={editor} class="cw-editor" display={computed(() -> tab.get() == "source" ? Display.Flex : Display.None)}
						value={value} language="haxe" label="Counter source" indentGuides={true} gutterMarkers={true} codeActions={actions}
						onInput={_ -> { changes.set(changes.get() + 1); activity.set(""); }} />
					<div class="cw-notes" display={computed(() -> tab.get() == "notes" ? Display.Flex : Display.None)}><text>Try typing, selecting text, or folding a block.</text><text>Tab indents. Shift+Tab removes indentation.</text><text>Undo and redo use the usual keyboard shortcuts.</text></div>
					<div class="cw-status"><text>Haxe</text><text>UTF-8</text><div class="grow" /><text>${activity.get() != "" ? activity.get() : changes.get() == 0 ? "Ready to edit" : changes.get() + " edits"}</text></div>
				</div>
				<div class="cw-sidebar">
					<div class="flex-row items-center justify-between"><text class="cw-section-title">Project settings</text><badge size={Sm} variant={Secondary}>Read only</badge></div>
					<code-view class="cw-preview" language="json" label="Project configuration" value={'{\n  "name": "counter",\n  "version": "1.0.0",\n  "entry": "Counter",\n  "features": [\n    "signals",\n    "native-text",\n    "theme-tokens"\n  ]\n}'} />
					<div class="cw-tip"><text class="cw-section-title">Actions beside your code</text><text class="cw-description">Run and Debug sit above the function. Click the gutter to toggle a breakpoint. Fold a block to hide its inline actions.</text></div>
					<div class="cw-key-row"><badge size={Sm} variant={Secondary} appearance={Outline}>Tab</badge><text class="cw-description">Indent selection</text></div>
					<div class="cw-key-row"><badge size={Sm} variant={Secondary} appearance={Outline}>⌘ Z / Ctrl Z</badge><text class="cw-description">Undo an edit</text></div>
				</div>
			</div>
		</div>;
	}
	static function main() {
		#if ashui_window
		WindowedApp.run(new WindowConfig().title("Code workbench").size(WIDTH, HEIGHT).theme(DefaultTheme.bundle()), page);
		#else
		var light = Sys.getEnv("SCHEME") == "light";
		ThemeState.init(DefaultTheme.bundle(), light ? Light : Dark);
		Snapshot.scene(light ? "CodeWorkbench-light" : "CodeWorkbench", WIDTH, HEIGHT, page, light ? 0xf8fafc : 0x0e1420);
		#end
	}
}
