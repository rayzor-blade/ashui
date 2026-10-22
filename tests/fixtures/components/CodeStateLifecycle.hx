import ashui.components.CodeEditor;
import ashui.components.code.CodeEditorState;
import ashui.css.Css;
import ashui.layout.LayoutTree;
import ashui.reactive.Owner;
import ashui.reactive.Reactive;
import ashui.theme.ThemeState;
import ashui.theme.themes.DefaultTheme;
import ashui.ui.Ref;

/** Data outlives a view, but its row pools, owners and capture hook do not. */
class CodeStateLifecycle {
	static function check(name:String, ok:Bool):Void {
		if (!ok) throw name;
		Sys.println('ok   $name');
	}
	static function main():Void {
		for (dark in [true, false]) {
			ThemeState.init(DefaultTheme.bundle(), dark ? Dark : Light);
			var source = 'class Example {\n\tfunction test() {\n\t\treturn 1;\n\t}\n}\n' + [for (i in 0...100) '// line $i\n'].join("");
			var value = signal(source), shown = signal(true), version = signal(0);
			var state = new CodeEditorState(value), ref = new Ref<CodeEditor>(), tree = new LayoutTree();
			var dispose:Void->Void = null;
			var root = Owner.root(tree, stop -> {
				dispose = stop;
				return <div width={760} height={400}>
					<for {revision in (shown.get() ? [version.get()] : [])}>
						<code-editor ref={ref} state={state} language="haxe" minimap={true} width={760} height={400}/>
					</for>
				</div>;
			});
			function settle() for (_ in 0...6) { Css.update(); tree.flush(); tree.computeLayout(root.node, 760, 400); }
			settle();
			var ed = ref.get(), document = ed.document;
			ed.applyEdits([{from: source.length, to: source.length, text: "// edit\n"}]);
			ed.select(1, 7); ed.toggleFold(1); settle();
			ed.scroll.jumpTo(0, 360); settle();
			var y = ed.scroll.y.get();
			check("fixture scrolls", y > 100);
			shown.set(false); settle();
			check("unmount drops the editor ref and state capture hook", ref.get() == null && !state.mounted);
			check("unmount retains document, navigation and folds", state.document == document && state.anchor == 1 && state.caret == 7 && state.scrollY == y && document.lines[1].folded);
			var hosts = 0;
			@:privateAccess for (host in ashui.ui.Component.hosts) if (Std.isOfType(host, CodeEditor)) hosts++;
			check("no editor host survives unmount", hosts == 0);
			shown.set(true); settle();
			ed = ref.get();
			check("remount reuses document data and restores navigation", ed.document == document && ed.editing.anchor.get() == 1 && ed.editing.caret.get() == 7 && ed.scroll.y.get() == y && ed.document.lines[1].folded);
			ed.undo(); settle(); check("undo survives disposing the view", value.get() == source);
			ed.redo(); settle(); check("redo survives disposing the view", value.get() == source + "// edit\n");
			ed.select(11, 14); ed.scroll.jumpTo(0, 220); settle();
			y = ed.scroll.y.get();
			version.set(version.get() + 1); settle();
			check("replacement captures the old view before its disposal", ref.get() != ed && state.mounted && ref.get().editing.anchor.get() == 11 && ref.get().editing.caret.get() == 14 && ref.get().scroll.y.get() == y);
			shown.set(false); settle(); value.set("external replacement");
			shown.set(true); settle(); ref.get().undo(); settle();
			check("an external replacement while unmounted clears incompatible undo", value.get() == "external replacement" && ref.get().editing.caret.get() <= value.get().length);
			dispose();
			check("root cleanup drops the state capture hook", !state.mounted);
		}
	}
}
