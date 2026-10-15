import ashui.components.CodeEditor;
import ashui.components.CodeView;
import ashui.components.code.CodeDocument;
import ashui.components.code.CodeSyntax;
import ashui.css.Css;
import ashui.css.Identity;
import ashui.input.Keyboard;
import ashui.input.Pointer;
import ashui.layout.LayoutTree;
import ashui.layout.Node;
import ashui.reactive.Owner;
import ashui.reactive.Reactive;
import ashui.theme.ThemeState;
import ashui.theme.themes.DefaultTheme;
import ashui.ui.Ref;

/** Real input, native grapheme geometry, incremental lexing and viewport bounds (e53597f). **/
class CodeComponents {
	static var checks = 0;
	static function check(name:String, ok:Bool, ?detail:Dynamic):Void {
		if (!ok) { if (detail != null) Sys.println(Std.string(detail)); throw name; }
		checks++; Sys.println('ok   $name');
	}
	static function key(k:window.Key, code:window.KeyCode):window.KeyEvent return Input(Code(code), k, None, Standard, Pressed, false, Unavailable);
	static function main() {
		var syntax = CodeSyntax.forLanguage("haxe");
		var source = 'class Greeting {\n    // not a fold: {\n    function hello() {\n        var text = "}";\n        return "Hello 🌍";\n    }\n}\n';
		var doc = new CodeDocument(source, syntax);
		check("folds ignore brackets in comments and strings", doc.lines[0].foldEnd == 6 && doc.lines[2].foldEnd == 5 && doc.lines[1].foldEnd == -1);
		doc.toggleFold(2); doc.toggleFold(0); doc.toggleFold(0);
		check("nested folds survive closing and reopening their parent", doc.lines[2].folded && doc.visible.indexOf(3) < 0 && doc.visible.indexOf(6) >= 0);
		doc.update(StringTools.replace(source, "Hello", "Goodbye"), syntax);
		check("single-line edit reuses unchanged highlight cache", doc.highlighted == 1, doc.highlighted);
		var multiline = new CodeDocument('/* start\ninside {\nend */\nvar a = 1;', syntax);
		check("block comments propagate to following lines", multiline.lines[1].tokens[0].kind == Comment && multiline.lines[1].foldEnd == -1);
		multiline.update('/* start */\ninside {\nend */\nvar a = 1;', syntax);
		check("changed lexical state re-highlights until it converges", multiline.lines[1].tokens[0].kind != Comment && multiline.highlighted >= 3);
		for (dark in [true, false]) {
			ThemeState.init(DefaultTheme.bundle(), dark ? Dark : Light);
			var hooks = LayoutTree.layoutHooks.length, tree = new LayoutTree(), dispose:Void->Void = null;
			var editor = new Ref<CodeEditor>(), viewer = new Ref<CodeView>();
			var value = signal(source), readOnly = signal(false), disabled = signal(false), changes = 0;
			var root = Owner.root(tree, stop -> {
				dispose = stop;
				return <div width={760} height={600} class="flex-col gap-4 p-4">
					<code-editor ref={editor} id="editor" language="haxe" value={value} readOnly={readOnly} disabled={disabled} height={270} indentGuides={true} onInput={_ -> changes++} />
					<code-view ref={viewer} id="viewer" language="json" value={'{"name": "Ashui",\n "ready": true\n}'} height={200} />
				</div>;
			});
			function settle() { tree.flush(); tree.computeLayout(root.node, 760, 600); }
			function press(k:window.Key, code:window.KeyCode, ?modifiers:window.Modifiers) { Keyboard.input(tree, key(k, code), modifiers); settle(); }
			settle();
			var ed = editor.get(), e = ed.editing;
			check("native font metrics have a usable line height", ed.metrics.lineHeight > 10 && ed.metrics.characterWidth > 3);
			ed.focus(); ed.select(0, 0); Keyboard.text(tree, "// Hello\n"); settle();
			check("typing writes the shared signal and callback", StringTools.startsWith(value.get(), "// Hello\n") && changes == 1);
			ed.undo(); settle(); check("undo restores text and selection", value.get() == source && e.caret.get() == 0);
			ed.redo(); settle(); check("redo restores the edit", StringTools.startsWith(value.get(), "// Hello\n"));
			ed.undo(); settle();
			ed.select(source.indexOf("{") + 1, source.indexOf("{") + 1); press(Named(Enter), Enter);
			check("Enter indents a new block line", value.get().indexOf("{\n    \n") >= 0, value.get());
			ed.undo(); settle();
			ed.select(0, 0); press(Named(Tab), Tab);
			check("Tab inserts indentation and retains focus", StringTools.startsWith(value.get(), "    class") && e.focused.get());
			ed.undo(); settle();
			ed.select(0, source.indexOf("    //")); press(Named(Tab), Tab);
			check("Tab indents the selected source lines", StringTools.startsWith(value.get(), "    class Greeting"));
			var indented = value.get(), selectedTo = e.caret.get();
			ed.undo(); settle();
			check("indent undo restores original selection", e.anchor.get() == 0 && e.caret.get() == source.indexOf("    //"));
			ed.redo(); settle(); check("indent redo restores selected indented lines", value.get() == indented && e.anchor.get() == 0 && e.caret.get() == selectedTo);
			ed.undo(); settle();
			ed.select(5, 5); press(Named(Backspace), Backspace); ed.undo(); settle();
			check("delete undo restores a collapsed caret", value.get() == source && e.caret.get() == 5 && e.anchor.get() == 5);
			ed.select(0, 0); readOnly.set(true); settle(); Keyboard.text(tree, "refused"); press(Named(Delete), Delete);
			check("read-only keeps source immutable", value.get() == source);
			readOnly.set(false); settle();
			disabled.set(true); settle(); e.replace("refused"); check("disabled editors refuse programmatic replacements too", value.get() == source);
			disabled.set(false); settle(); ed.focus();
			ed.toggleFold(0); settle();
			check("folding keeps original source and line numbers", value.get() == source && ed.document.visible.length == 2 && ed.document.visible[1] == 7);
			ed.select(source.indexOf("return"), source.indexOf("return")); settle();
			check("programmatic selection reveals folded ancestors", !ed.document.lines[0].folded);
			var emoji = source.indexOf("🌍"); ed.select(emoji, emoji); press(Named(ArrowRight), ArrowRight);
			check("right arrow crosses one native emoji grapheme", e.caret.get() == emoji + "🌍".length, [e.caret.get(), emoji]);
			ed.select(source.indexOf("return"), source.indexOf("return"));
			Keyboard.composition(tree, "日本", 1); settle();
			check("IME composition is displayed without committing the source", e.display().indexOf("日本return") >= 0 && value.get() == source);
			Keyboard.composition(tree, "", -1); Keyboard.text(tree, "日本"); settle();
			check("IME commit is one undoable source edit", value.get().indexOf("日本return") >= 0);
			ed.undo(); settle();
			var foldId = Css.query(tree, ed.node.id, ".ui-code-fold")[0], fold = tree.getBounds(Identity.of(tree, foldId).node);
			Pointer.move(tree, fold.x + fold.width / 2, fold.y + fold.height / 2); Pointer.press(tree); Pointer.release(tree); settle();
			check("existing icon button toggles a gutter fold", ed.document.lines[0].folded);
			press(Named(Enter), Enter); check("keyboard activates the focused fold button", !ed.document.lines[0].folded);
			var view = viewer.get(); view.focus(); view.select(0, 0); Keyboard.text(tree, "refused"); settle();
			check("CodeView supports selection without mutation", StringTools.startsWith(view.value.get(), "{\"name\""));
			var large = [for (i in 0...5000) 'var item$i = $i;'].join("\n");
			value.set(large); settle();
			check("large document retains all source lines", ed.document.lines.length == 5000);
			check("only viewport lines have UI nodes", Css.query(tree, ed.node.id, ".ui-code-line").length < 40);
			var pane = tree.getBounds(ed.scroll.node);
			Pointer.move(tree, pane.x + pane.width / 2, pane.y + pane.height / 2); Pointer.wheel(tree, 0, -80); settle();
			check("wheel scrolls the code viewport", ed.scroll.y.get() > 0);
			ed.scroll.jumpTo(0, 3000); settle();
			check("scrolling renders later source rows", Std.parseInt(ashui.ui.Text.at(Css.query(tree, ed.node.id, ".ui-code-line-number")[0]).text()) > 50);
			check("shaped line cache is bounded", @:privateAccess ed.metrics.recent.length <= 96);
			value.set("reset"); settle(); ed.undo(); settle();
			check("external source reset clears incompatible undo history", value.get() == "reset");
			dispose(); ashui.animation.AnimationScheduler.main.tick(1); tree.flush();
			check("disposing code controls releases layout hooks", LayoutTree.layoutHooks.length == hooks);
			tree.dispose();
		}
		Sys.println('$checks checks: ALL PASSED');
	}
}
