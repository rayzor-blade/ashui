import ashui.components.Badge;
import ashui.components.CodeEditor;
import ashui.core.render.Snapshot;
import ashui.reactive.Reactive;
import ashui.theme.ThemeState;
import ashui.theme.themes.DefaultTheme;
import ashui.ui.Ref;

/** Native selection and folded source snapshots, in either scheme (e53597f). **/
class CodeEditorStates {
	static function main() {
		var light = Sys.getEnv("SCHEME") == "light";
		ThemeState.init(DefaultTheme.bundle(), light ? Light : Dark);
		var source = signal('class Welcome {\n    static function main() {\n        /* Braces in strings are not folds. */\n        var greeting = "Hello, world { 🌍 }";\n        var colors = [\n            "amber",\n            "violet",\n            "ocean"\n        ];\n        trace(greeting);\n    }\n}\n');
		var editor = new Ref<CodeEditor>();
		var build = () -> <div class="bg-background p-6 flex-col gap-4" width={820} height={460}>
			<div class="flex-row items-center justify-between"><text class="text-lg font-semibold">Welcome.hx</text><badge variant={Secondary}>Selection &amp; folding</badge></div>
			<code-editor ref={editor} value={source} language="haxe" class="grow min-h-0" height={0} indentGuides={true} />
		</div>;
		Snapshot.sequence(light ? "CodeEditorStates-light" : "CodeEditorStates", 820, 460, build, 30, 3, (frame, tree, root) -> {
			if (frame == 1) {
				editor.get().focus();
				var from = source.get().indexOf('"Hello');
				editor.get().select(from, from + '"Hello, world { 🌍 }"'.length);
			}
			if (frame == 2) editor.get().toggleFold(4);
		}, light ? 0xf8fafc : 0x0e1420);
	}
}
