import ashui.components.Badge;
import ashui.components.CodeEditor;
import ashui.core.render.Snapshot;
import ashui.reactive.Reactive;
import ashui.theme.ThemeState;
import ashui.theme.themes.DefaultTheme;
import ashui.ui.Ref;

/** Change bars in the gutter minimap, a deletion's boundary marker and a whole-line decoration marked in the minimap (SCHEME=light) (96ae277, 118ce57). **/
class CodeEditorChangeMarks {
	static function main() {
		var light = Sys.getEnv("SCHEME") == "light";
		ThemeState.init(DefaultTheme.bundle(), light ? Light : Dark);
		var source = signal([for (i in 0...60) 'var value$i = $i;'].join("\n"));
		var editor = new Ref<CodeEditor>();
		var build = () -> <div class="bg-background p-6 flex-col gap-4" width={820} height={460}>
			<div class="flex-row items-center justify-between"><text class="text-lg font-semibold">Changes.hx</text><badge variant={Secondary}>Change marks</badge></div>
			<code-editor ref={editor} value={source} language="haxe" class="grow min-h-0" height={0} minimap={true} gutterMarkers={true} />
		</div>;
		Snapshot.sequence(light ? "CodeEditorChangeMarks-light" : "CodeEditorChangeMarks", 820, 460, build, 30, 2, (frame, tree, root) -> {
			if (frame == 1) {
				var ed = editor.get();
				ed.markers("scm", [
					{line: 3, className: "ui-code-change-added", bar: true, minimap: true},
					{line: 4, className: "ui-code-change-added", bar: true, minimap: true},
					{line: 8, className: "ui-code-change-modified", bar: true, minimap: true},
					{line: 8, className: "ui-code-marker-breakpoint"},
					{line: 12, className: "ui-code-change-removed", boundary: true, minimap: true, title: "2 lines deleted"}
				]);
				var s = ed.document.lines[20].start, e = ed.document.lines[23].start - 1;
				ed.decorate("find", [{from: s, to: e, className: "ui-code-change-added", wholeLine: true, minimap: true}]);
			}
		}, light ? 0xf8fafc : 0x0e1420);
	}
}
