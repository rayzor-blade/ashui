import ashui.components.CodeEditor;
import ashui.css.Css;
import ashui.input.Pointer;
import ashui.layout.LayoutTree;
import ashui.layout.Node;
import ashui.reactive.Owner;
import ashui.reactive.Signal;
import ashui.theme.ThemeState;
import ashui.theme.themes.DefaultTheme;
import ashui.ui.Ref;

class CodeGutterColumns {
	static var checks = 0;

	static function check(name:String, ok:Bool):Void {
		if (!ok)
			throw name;
		checks++;
		Sys.println('ok   $name');
	}

	static function main():Void {
		ThemeState.init(DefaultTheme.bundle(), Light);
		var plain = [for (i in 0...120) 'line $i'].join("\n");
		var value = Signal.make(plain),
			compact = new Ref<CodeEditor>(),
			stable = new Ref<CodeEditor>(),
			reserved = new Ref<CodeEditor>();
		var tree = new LayoutTree(), stop = () -> {};
		var root = Owner.root(tree, dispose -> {
			stop = dispose;
			return <div class="flex flex-row" width={800} height={300}>
				<code-editor ref={compact} value={value} language="haxe" gutterMarkers={true} compactGutter={true} width={400} height={300}/>
				<code-editor ref={stable} value={value} language="haxe" gutterMarkers={true} compactGutter={true} stableGutter={true} width={400} height={300}/>
				<code-editor ref={reserved} value={value} language="haxe" gutterMarkers={true} width={400} height={300}/>
			</div>;
		});
		function settle():Void
			for (_ in 0...6) {
				Css.update();
				tree.flush();
				tree.computeLayout(root.node, 800, 300);
			}
		function count(editor:CodeEditor, selector:String):Int
			return Css.query(tree, editor.node.id, selector).length;
		function gutter(editor:CodeEditor):Float
			return tree.getBounds(new Node(Css.query(tree, editor.node.id, ".ui-code-gutter")[0])).width;
		function near(a:Float, b:Float):Bool
			return Math.abs(a - b) < .1;
		settle();
		var editor = compact.get(), base = gutter(editor);
		check("stable compact view starts without unused columns", near(gutter(stable.get()), base));
		stable.get().markers("changes", [{line:1, className:"ui-code-change-added", bar:true}]);
		settle();
		check("stable gutter ignores change bars", near(gutter(stable.get()), base));
		stable.get().markers("action", [{line:110, className:"ui-code-marker-breakpoint"}]);
		settle();
		var activated = gutter(stable.get());
		stable.get().markers("action", []);
		settle();
		check("stable gutter retains geometry without retaining stale markers", near(activated, base + 18)
			&& near(gutter(stable.get()), activated) && stable.get().annotations.markerAt(110) == null);
		check("unused marker and fold columns collapse", near(gutter(reserved.get()) - base,
			40) && count(editor, ".ui-code-marker-slot") == 0 && count(editor, ".ui-code-fold-slot") == 0);
		check("default gutter keeps an empty breakpoint target", count(reserved.get(),
			".ui-code-marker-slot") > 0 && count(reserved.get(), ".ui-code-fold-slot") > 0);
		var clicked = -1;
		reserved.get().onGutterClick = (line, _) -> clicked = line;
		var slot = tree.getScrolledBounds(new Node(Css.query(tree, reserved.get().node.id, ".ui-code-marker-slot")[0]));
		Pointer.move(tree, slot.x + slot.width / 2, slot.y + slot.height / 2);
		Pointer.press(tree);
		Pointer.release(tree);
		check("empty reserved gutter still accepts breakpoint clicks", clicked == 0);
		editor.markers("action", [{line: 110, className: "ui-code-marker-breakpoint"}]);
		settle();
		check("offscreen markers activate the whole column", near(gutter(editor), base + 18) && count(editor, ".ui-code-marker-slot") > 0);
		editor.scroll.scrollTo(0, 700);
		settle();
		check("scrolling keeps marker column width stable", near(gutter(editor), base + 18));
		editor.scroll.scrollTo(0, 0);
		editor.markers("action", []);
		settle();
		check("clearing markers releases their column", near(gutter(editor), base));
		editor.markers("changes", [
			{line: 1, className: "ui-code-change-added", bar: true},
			{line: 2, className: "ui-code-change-removed", boundary: true}
		]);
		settle();
		check("change bars and boundaries do not reserve the icon column", near(gutter(editor), base)
			&& count(editor, ".ui-code-marker-slot") == 0
			&& editor.annotations.barAt(1) != null
			&& editor.annotations.boundaryAt(2) != null);
		editor.markers("changes", []);
		value.set("class Example {\n\tstatic function main() {\n\t\ttrace(1);\n\t}\n}\n");
		settle();
		var foldWidth = gutter(editor);
		check("foldable documents activate only the fold column", near(gutter(reserved.get()) - foldWidth,
			18) && count(editor, ".ui-code-fold-slot") > 0 && count(editor, ".ui-code-marker-slot") == 0);
		var fold = tree.getScrolledBounds(new Node(Css.query(tree, editor.node.id, ".ui-code-fold")[0]));
		var rows = editor.document.visible.length;
		Pointer.move(tree, fold.x + fold.width / 2, fold.y + fold.height / 2);
		Pointer.press(tree);
		Pointer.release(tree);
		settle();
		check("compact fold controls stay clickable without moving the column", editor.document.visible.length < rows
			&& near(gutter(editor), foldWidth));
		value.set("one\ntwo\n");
		settle();
		check("stable columns survive edits removing folds and markers", count(stable.get(), ".ui-code-fold-slot") > 0
			&& near(gutter(stable.get()), gutter(reserved.get())));
		check("removing folds releases their column", count(editor, ".ui-code-fold-slot") == 0
			&& near(gutter(reserved.get()) - gutter(editor), 40));
		var before = editor.rectAt(0);
		editor.markers("action", [{line: 0, className: "ui-code-marker-breakpoint"}]);
		settle();
		var after = editor.rectAt(0);
		check("character rectangles follow the activated gutter", near(after.x - before.x, 18));
		check("hit testing follows the activated gutter", editor.offsetAt(after.x + 1, after.y + after.height / 2) == 0);
		editor.markers("action", []);
		settle();
		var at = editor.rectAt(4);
		Pointer.move(tree, at.x + 1, at.y + at.height / 2);
		Pointer.press(tree);
		Pointer.release(tree);
		settle();
		check("text clicks follow the collapsed gutter", editor.editing.caret.get() == 4 && compact.get() == editor);
		stop();
		tree.dispose();
		Sys.println('$checks checks: ALL PASSED');
	}
}
