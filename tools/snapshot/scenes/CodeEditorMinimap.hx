import ashui.components.Badge;
import ashui.components.CodeEditor;
import ashui.core.render.Snapshot;
import ashui.reactive.Reactive;
import ashui.theme.ThemeState;
import ashui.theme.themes.DefaultTheme;
import ashui.ui.Ref;

/** A long source with its minimap, in either scheme, scrolled into the middle. **/
class CodeEditorMinimap {
	static function main() {
		var light = Sys.getEnv("SCHEME") == "light";
		ThemeState.init(DefaultTheme.bundle(), light ? Light : Dark);
		var block = 'class Greeting {\n    // Greets a name, in the language asked for.\n    static function hello(name:String, loud = false):String {\n        var text = "Hello, " + name + "!";\n        for (i in 0...3) {\n            if (i % 2 == 0) text += " " + Std.string(i * 42);\n        }\n        return loud ? text.toUpperCase() : text;\n    }\n}\n\n';
		var source = signal([for (i in 0...150) block].join(""));
		var editor = new Ref<CodeEditor>();
		var build = () -> <div class="bg-background p-6 flex-col gap-4" width={820} height={460}>
			<div class="flex-row items-center justify-between"><text class="text-lg font-semibold">Greeting.hx</text><badge variant={Secondary}>Minimap</badge></div>
			<code-editor ref={editor} value={source} language="haxe" class="grow min-h-0" height={0} minimap={true} />
		</div>;
		Snapshot.sequence(light ? "CodeEditorMinimap-light" : "CodeEditorMinimap", 820, 460, build, 30, 3, (frame, tree, root) -> {
			if (frame == 1) editor.get().scroll.jumpTo(0, 6000);
			if (frame == 2) editor.get().scroll.jumpTo(0, 200);
		}, light ? 0xf8fafc : 0x0e1420);
	}
}
