import ashui.components.Badge;
import ashui.components.Button;
import ashui.components.CodeEditor;
import ashui.core.render.Snapshot;
import ashui.layout.Element;
import ashui.reactive.Owner;
import ashui.reactive.Reactive;
import ashui.theme.ThemeState;
import ashui.theme.themes.DefaultTheme;
import ashui.ui.Ref;

/** Elements between lines of the editor: a conflict's choices above it and a peeked change below a line, in either scheme (SCHEME=light) (e23bd16). **/
class CodeEditorZones {
	static function main() {
		var light = Sys.getEnv("SCHEME") == "light";
		ThemeState.init(DefaultTheme.bundle(), light ? Light : Dark);
		var source = signal('class Merge {\n    static function main() {\n        var greeting = "Hello";\n        trace(greeting);\n        var total = 1 + 2;\n        trace(total);\n    }\n\n    static function other() {\n        return 42;\n    }\n}\n');
		var editor = new Ref<CodeEditor>();
		var build = () -> <div class="bg-background p-6 flex-col gap-4" width={820} height={460}>
			<div class="flex-row items-center justify-between"><text class="text-lg font-semibold">Merge.hx</text><badge variant={Secondary}>Zones</badge></div>
			<code-editor ref={editor} value={source} language="haxe" class="grow min-h-0" height={0} minimap={true} gutterMarkers={true} />
		</div>;
		Snapshot.sequence(light ? "CodeEditorZones-light" : "CodeEditorZones", 820, 460, build, 30, 3, (frame, tree, root) -> {
			if (frame == 1) {
				var ed = editor.get();
				var choices:Element = Owner.root(tree, _ -> <div class="flex-row items-center gap-2 px-3 py-1 border-b"><text class="text-sm text-secondary">Current change</text><button size={Sm} variant={Outline}>Accept current</button><button size={Sm} variant={Outline}>Accept incoming</button></div>);
				var peek:Element = Owner.root(tree, _ -> <div class="flex-col gap-1 p-3 border-y bg-surface"><text class="text-sm font-semibold">Changed in 3 commits</text><text class="text-sm text-secondary">greeting was "Hi" before 4b1e2c9; the previous value stays in history.</text></div>);
				ed.zone("conflict", [{line: 1, element: choices}]);
				ed.zone("peek", [{line: 3, element: peek}]);
			}
			if (frame == 2) {
				var ed = editor.get();
				ed.select(ed.document.lines[8].start + 4, ed.document.lines[8].start + 4);
			}
		}, light ? 0xf8fafc : 0x0e1420);
	}
}
