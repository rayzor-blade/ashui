import ashui.components.Badge;
import ashui.components.CodeEditor;
import ashui.core.render.Snapshot;
import ashui.reactive.Reactive;
import ashui.theme.ThemeState;
import ashui.theme.themes.DefaultTheme;
import ashui.ui.Ref;

/** The popover of documentation beside a call, and a diagnostic's message, in either scheme (495aa31). **/
class CodeEditorHint {
	static function main() {
		var light = Sys.getEnv("SCHEME") == "light";
		ThemeState.init(DefaultTheme.bundle(), light ? Light : Dark);
		var source = signal('class Welcome {\n    static function main() {\n        var greeting = "Hello, world";\n        var count:Int = "three";\n        trace(greeting, count);\n    }\n}\n');
		var editor = new Ref<CodeEditor>();
		var build = () -> <div class="bg-background p-6 flex-col gap-4" width={820} height={460}>
			<div class="flex-row items-center justify-between"><text class="text-lg font-semibold">Welcome.hx</text><badge variant={Secondary}>Hints</badge></div>
			<code-editor ref={editor} value={source} language="haxe" class="grow min-h-0" height={0} />
		</div>;
		var shot = Sys.getEnv("HINT") == "error" ? "error" : "docs";
		Snapshot.sequence((light ? "CodeEditorHint-light-" : "CodeEditorHint-") + shot, 820, 460, build, 30, 3, (frame, tree, root) -> {
			if (frame != 1) return;
			var ed = editor.get();
			function at(line:Int, text:String) return ed.document.lines[line].start + ed.document.lines[line].text.indexOf(text);
			if (shot == "error") {
				ed.decorate("problems", [{from: at(3, '"three"'), to: at(3, '"three"') + 7, className: "ui-code-squiggle-error", title: "String should be Int\nFor function argument 'count'"}]);
				ed.showHint({from: at(3, '"three"'), to: at(3, '"three"') + 7, docs: "String should be Int\nFor function argument 'count'", className: "ui-code-hint-error"}, true);
			} else
				ed.showHint({
					from: at(4, "trace"), to: at(4, "trace") + 5,
					signature: "static function trace(v:Dynamic, ?infos:PosInfos):Void",
					docs: "Print the value v on the default output.\n\nThe output depends on the platform: it is the console on native targets and the browser's console on JavaScript. The position of the call is added when infos is given."
				}, true);
		}, light ? 0xf8fafc : 0x0e1420);
	}
}
