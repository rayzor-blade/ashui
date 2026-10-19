import ashui.components.Badge;
import ashui.components.CodeEditor;
import ashui.core.render.Snapshot;
import ashui.reactive.Reactive;
import ashui.theme.ThemeState;
import ashui.theme.themes.DefaultTheme;
import ashui.ui.Ref;

/** Decorations and gutter markers: a stopped line, a breakpoint, and diagnostics, in either scheme (495aa31). **/
class CodeEditorAnnotations {
	static function main() {
		var light = Sys.getEnv("SCHEME") == "light";
		ThemeState.init(DefaultTheme.bundle(), light ? Light : Dark);
		var source = signal('class Welcome {\n    static function main() {\n        var greeting = "Hello, world";\n        var count:Int = "three";\n        trace(greeting, count);\n        trace(missing);\n    }\n}\n');
		var editor = new Ref<CodeEditor>();
		var build = () -> <div class="bg-background p-6 flex-col gap-4" width={820} height={460}>
			<div class="flex-row items-center justify-between"><text class="text-lg font-semibold">Welcome.hx</text><badge variant={Secondary}>Debugging</badge></div>
			<code-editor ref={editor} value={source} language="haxe" class="grow min-h-0" height={0} gutterMarkers={true} />
		</div>;
		Snapshot.sequence(light ? "CodeEditorAnnotations-light" : "CodeEditorAnnotations", 820, 460, build, 30, 1, (frame, tree, root) -> {
			var ed = editor.get();
			function at(line:Int, text:String) return ed.document.lines[line].start + ed.document.lines[line].text.indexOf(text);
			ed.markers("debug", [{line: 2, className: "ui-code-marker-breakpoint", title: "Breakpoint"}, {line: 4, className: "ui-code-marker-breakpoint"}]);
			ed.decorate("stopped", [{from: ed.document.lines[4].start, to: ed.document.lines[4].start, className: "ui-code-line-current", wholeLine: true}]);
			ed.decorate("problems", [
				{from: at(3, '"three"'), to: at(3, '"three"') + 7, className: "ui-code-squiggle-error", title: "String should be Int"},
				{from: at(5, "missing"), to: at(5, "missing") + 7, className: "ui-code-squiggle-error", title: "Unknown identifier : missing"},
				{from: at(2, "greeting"), to: at(2, "greeting") + 8, className: "ui-code-squiggle-warning", title: "Unused"}
			]);
		}, light ? 0xf8fafc : 0x0e1420);
	}
}
