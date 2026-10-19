import ashui.components.Badge;
import ashui.components.CodeEditor;
import ashui.core.render.Snapshot;
import ashui.reactive.Reactive;
import ashui.theme.ThemeState;
import ashui.theme.themes.DefaultTheme;
import ashui.ui.Ref;

/** The completion list under the caret, with the selected row's documentation, in either scheme (495aa31). **/
class CodeEditorCompletion {
	static function main() {
		var light = Sys.getEnv("SCHEME") == "light";
		ThemeState.init(DefaultTheme.bundle(), light ? Light : Dark);
		var source = signal('class Welcome {\n    static function main() {\n        var greeting = "Hello, world";\n        greeting.to\n    }\n}\n');
		var editor = new Ref<CodeEditor>();
		var build = () -> <div class="bg-background p-6 flex-col gap-4" width={820} height={460}>
			<div class="flex-row items-center justify-between"><text class="text-lg font-semibold">Welcome.hx</text><badge variant={Secondary}>Completion</badge></div>
			<code-editor ref={editor} value={source} language="haxe" class="grow min-h-0" height={0} />
		</div>;
		Snapshot.sequence((light ? "CodeEditorCompletion-light" : "CodeEditorCompletion"), 820, 460, build, 30, 3, (frame, tree, root) -> {
			if (frame != 1) return;
			var ed = editor.get();
			var line = ed.document.lines[3], at = line.start + line.text.length;
			ed.focus();
			ed.select(at, at);
			ed.showCompletions([
				{label: "toString", kind: "method", detail: "():String", docs: "Returns a String representation of the value.\n\nThe result is for display, not for parsing."},
				{label: "toLowerCase", kind: "method", detail: "():String", docs: "Returns the String with every letter lower case."},
				{label: "toUpperCase", kind: "method", detail: "():String", docs: "Returns the String with every letter upper case."},
				{label: "toCharArray", kind: "method", detail: "():Array<String>"},
				{label: "toInt", kind: "function", detail: "(s:String):Null<Int>"},
				{label: "length", kind: "property", detail: "Int", filter: "tolength"}
			], at - 2);
		}, light ? 0xf8fafc : 0x0e1420);
	}
}
