import ashui.components.CodeEditor;
import ashui.css.Css;
import ashui.layout.LayoutTree;
import ashui.reactive.Owner;
import ashui.reactive.Reactive;
import ashui.theme.ThemeState;
import ashui.theme.themes.DefaultTheme;
import ashui.ui.Div;
import ashui.ui.Ref;

/** A zone, an element between two lines, moves the rows after it and scrolls with the text; positions, folds, edits and the minimap agree with it. **/
class CodeZonesEditor {
	static var checks = 0;

	static function check(name:String, ok:Bool, ?detail:Dynamic):Void {
		if (!ok)
			throw name + (detail == null ? "" : ' ($detail)');
		checks++;
		Sys.println('ok   $name');
	}

	static function main():Void {
		ThemeState.init(DefaultTheme.bundle(), Light);
		var source = [for (i in 0...300) 'line $i {' + (i % 50 == 5 ? '\n    inner\n}' : '}')].join("\n");
		var value = signal(source), ref = new Ref<CodeEditor>(), tree = new LayoutTree(), stop:Void->Void = null;
		var root = Owner.root(tree, s -> {
			stop = s;
			return <div width={700} height={400}><code-editor ref={ref} value={value} language="haxe" minimap={true} gutterMarkers={true} width={700} height={400}/></div>;
		});
		function settle()
			for (_ in 0...8) {
				Css.update();
				tree.flush();
				tree.computeLayout(root.node, 700, 400);
			}
		settle();
		var ed = ref.get(), lh = ed.metrics.lineHeight;
		// Elements an app makes under an owner of the tree, as it would in its own view code.
		function zoneBox(height:Float):Div
			return Owner.root(tree, _ -> new Div({classes: ["probe-zone"], height: height}, tree));
		var before = ed.rectAt(ed.document.lines[12].start);
		check("a line has a rectangle before any zone", before != null && lh > 0, before);
		var box = zoneBox(60);
		ed.zone("review", [{line: 10, element: box}]);
		settle();
		var after = ed.rectAt(ed.document.lines[12].start), upper = ed.rectAt(ed.document.lines[10].start);
		check("a line below the zone is its element's height lower", after != null && Math.abs(after.y - before.y - 60) < 1, [before, after]);
		check("the line the zone follows has not moved", upper != null && Math.abs(upper.y - ed.rectAt(ed.document.lines[10].start).y) < 0.01);
		var zoneBounds = tree.getBounds(box.node);
		check("the zone sits directly below its line and is as high as its element", zoneBounds != null && Math.abs(zoneBounds.height - 60) < 1 && Math.abs(zoneBounds.y - (upper.y + lh)) < 2, [zoneBounds, upper]);
		check("the line after the zone starts where the zone ends", Math.abs(ed.rectAt(ed.document.lines[11].start).y - (zoneBounds.y + zoneBounds.height)) < 2, [ed.rectAt(ed.document.lines[11].start), zoneBounds]);
		var inside = ed.offsetAt(after.x + 4, upper.y + lh + 30);
		check("a point in the zone is over no character", inside == -1, inside);
		check("a point on a line below it is that line's", ed.offsetAt(after.x + 1, after.y + 2) == ed.document.lines[12].start, ed.offsetAt(after.x + 1, after.y + 2));
		// Click through to the caret: a press on a line below the zone puts the caret on it.
		ashui.input.Pointer.move(tree, after.x + 2, after.y + lh / 2);
		ashui.input.Pointer.press(tree);
		ashui.input.Pointer.release(tree);
		settle();
		check("pressing a line below a zone puts the caret on that line", ed.document.lineAt(ed.editing.caret.get()) == 12, ed.document.lineAt(ed.editing.caret.get()));

		// Scrolling far: the window of rows is found through the zones, and the zone leaves with its row.
		ed.scroll.jumpTo(0, 4000);
		settle();
		var top = ed.rectAt(ed.document.lines[200].start);
		check("far down, rows are drawn and located", ed.shownRowCount() > 5, ed.shownRowCount());
		ed.scroll.jumpTo(0, 0);
		settle();

		// A second zone adds up, and replacing the owner's set takes the first away.
		var other = zoneBox(30);
		ed.zone("blame", [{line: 3, element: other}]);
		settle();
		var both = ed.rectAt(ed.document.lines[12].start);
		check("two owners' zones add up", Math.abs(both.y - before.y - 90) < 1, [before, both]);
		ed.zone("review", []);
		settle();
		check("clearing an owner's zones moves the rows back by them", Math.abs(ed.rectAt(ed.document.lines[12].start).y - before.y - 30) < 1);
		check("and takes their element out of the editor", tree.getBounds(box.node) == null);

		// Follow: the zone stays with its line when text is added above.
		ed.zone("review", [{line: 20, element: zoneBox(40)}], true);
		settle();
		ed.applyEdits([{from: 0, to: 0, text: "inserted line\nanother\n"}]);
		settle();
		check("a following zone moves down with the lines above it", ed.zoneLinesOf("review")[0] == 22, ed.zoneLinesOf("review"));
		check("a zone that does not follow stays on its line number", ed.zoneLinesOf("blame")[0] == 3);

		// A fold hides the zone of a line folded away.
		var folded = -1;
		for (i in 0...ed.document.lines.length)
			if (ed.document.lines[i].foldEnd > i + 1) {
				folded = i;
				break;
			}
		ed.zone("inside", [{line: folded + 1, element: zoneBox(20)}]);
		settle();
		var withZone = ed.rectAt(ed.document.lines[folded + 4].start);
		ed.toggleFold(folded);
		settle();
		var holders = [for (id in Css.query(tree, root.node.id, ".ui-code-zone")) tree.getBounds(new ashui.layout.Node(id))];
		check("folding a zone's line away leaves no space for it", ed.zoneLinesOf("inside")[0] == folded + 1 && holders.length >= 3);
		ed.toggleFold(folded);
		settle();
		check("unfolding gives the zone back its space", Math.abs(ed.rectAt(ed.document.lines[folded + 4].start).y - withZone.y) < 1);

		// The minimap's slider covers the rows on screen, with zones in the way.
		var sliders = Css.query(tree, root.node.id, ".ui-code-minimap-slider");
		check("the minimap has its slider with zones present", sliders.length == 1 && tree.getBounds(new ashui.layout.Node(sliders[0])).height > 0);

		stop();
		tree.dispose();
		Sys.println('$checks checks: ALL PASSED');
	}
}
