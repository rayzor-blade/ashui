import ashui.css.Css;
import ashui.css.Identity;
import ashui.layout.LayoutTree;
import ashui.layout.Node;
import ashui.layout.Prop;
import ashui.reactive.Owner;
import ashui.reactive.Signal;
import ashui.types.Style;
import ashui.ui.Div;
import ashui.ui.Table.Cell;

/** Spanning-cell column constraints: git-bug 4bcdb95, umbrella 8780d6b. **/
class TableSpans {
	static function check(name:String, ok:Bool, ?detail:Dynamic) {
		if (!ok) {
			if (detail != null) Sys.println(Std.string(detail));
			throw name;
		}
		Sys.println('ok   $name');
	}
	static function node(tree:LayoutTree, id:String):Node return new Node(Css.query(tree, tree.root.id, "#" + id)[0]);
	static function box(tree:LayoutTree, id:String) return tree.getBounds(node(tree, id));
	static function widths(tree:LayoutTree, id:String) return Cell.at(node(tree, id).id).flow.widths();
	static function near(a:Float, b:Float):Bool return Math.abs(a - b) < 1.5;
	static function settle(tree:LayoutTree, root:Div) {
		tree.flush();
		tree.computeLayout(root.node, 700, 900);
	}

	static function main() {
		ashui.theme.ThemeState.init(ashui.theme.themes.DefaultTheme.bundle(), Light);
		var tree = new LayoutTree(), text = Signal.make("a spanning heading with many short words"), show = Signal.make(true);
		var dispose:Void->Void = null;
		var root:Div = Owner.root(tree, stop -> {
			dispose = stop;
			return <div width={700} height={900} flexDirection={Column}>
				<table id="auto" width={600}>
					<thead><tr><th id="heading" colspan={2}>{text}</th><th id="outside">Count</th></tr></thead>
					<tbody>
						<tr><td id="a">A</td><td id="b">B</td><td id="c">Items</td></tr>
						<if {show}><tr><td>x</td><td colspan={2} id="overlap">Incomprehensibilities</td></tr></if>
					</tbody>
				</table>
				<table id="only" width={320}>
					<tbody><tr><td id="onlySpan" colspan={3}>the only content sizes all three empty columns</td></tr></tbody>
				</table>
				<table id="mixed" width={400}>
					<colgroup><col width="70.5" /><col /><col width="1*" /></colgroup>
					<thead><tr><th id="mixedSpan" colspan={2}>Incomprehensibilities</th><th>Other</th></tr></thead>
					<tbody><tr><td id="pixel">x</td><td id="automatic">x</td><td id="star">x</td></tr></tbody>
				</table>
				<table id="relative" width={400}>
					<colgroup><col width="25%" /><col /><col width="1*" /></colgroup>
					<thead><tr><th id="relativeSpan" colspan={2}>Incomprehensibilities</th><th>x</th></tr></thead>
					<tbody><tr><td id="percentage">x</td><td id="relativeAuto">x</td><td id="relativeStar">x</td></tr></tbody>
				</table>
			</div>;
		});
		settle(tree, root);
		var a = box(tree, "a"), b = box(tree, "b"), c = box(tree, "c"), heading = box(tree, "heading"), overlap = box(tree, "overlap");
		check("a colspan's preferred width influences its automatic columns", a.width + b.width > c.width * 1.5, [a.width, b.width, c.width]);
		check("a spanning header covers the same body columns", near(heading.x, a.x) && near(heading.width, a.width + b.width));
		check("overlapping spans retain both unbreakable width constraints", heading.width >= widths(tree, "heading").min - 1
			&& overlap.width >= widths(tree, "overlap").min - 1 && near(overlap.x, b.x), [heading, overlap]);
		var height = box(tree, "auto").height;
		settle(tree, root);
		check("overlapping span layout settles within one compute", near(box(tree, "auto").height, height));
		var only = widths(tree, "onlySpan");
		var row = new Node(tree.ancestors(node(tree, "onlySpan").id)[0]);
		var rows = tree.getBounds(row);
		check("a table made entirely of spanning cells sizes its empty tracks", only.min > 0 && near(box(tree, "onlySpan").width, rows.width));
		check("a spanning cell preserves explicit pixel and star settings", near(box(tree, "pixel").width, 70.5)
			&& box(tree, "mixedSpan").width >= widths(tree, "mixedSpan").min - 1 && box(tree, "star").width > 0);
		var relative = box(tree, "relativeSpan"), relativeAuto = box(tree, "relativeAuto");
		check("a percentage track contributes to a spanning cell's width", near(box(tree, "percentage").width, 99.5)
			&& relative.width >= widths(tree, "relativeSpan").min - 1, [relative, relativeAuto]);
		node(tree, "relative").set(Prop.Width, 600);
		settle(tree, root);
		check("percentage resize releases the automatic part of a span", near(box(tree, "percentage").width, 149.5)
			&& box(tree, "relativeAuto").width < relativeAuto.width - 20, [relativeAuto.width, box(tree, "relativeAuto").width]);
		var relativeHeight = box(tree, "relative").height;
		settle(tree, root);
		check("percentage span resize settles in the same frame", near(box(tree, "relative").height, relativeHeight));

		var before = box(tree, "heading").width;
		text.set("x");
		settle(tree, root);
		check("shorter reactive spanning text releases column preference", box(tree, "heading").width < before - 20, [before, box(tree, "heading").width]);
		show.set(false);
		settle(tree, root);
		check("removing an overlapping span releases its column minimum", box(tree, "b").width < b.width - 10, [b.width, box(tree, "b").width]);
		var identity = Identity.of(tree, node(tree, "heading").id);
		var beforeFont = box(tree, "heading").width;
		text.set("an updated spanning title");
		identity.setInline("font-size", "32px");
		settle(tree, root);
		check("spanning text and font changes invalidate the cached constraints", box(tree, "heading").width > beforeFont + 20);
		var flow = Cell.at(node(tree, "heading").id).flow;
		var changed = 0, stop = flow.onWidthsChanged(() -> changed++);
		settle(tree, root);
		settle(tree, root);
		check("unchanged spans neither remeasure nor schedule another frame", changed == 0 && !tree.flush(), changed);
		stop();
		dispose();
		check("span subscriptions leave with their table owner", @:privateAccess !ashui.text.InlineFlow.measured.exists(tree));
		tree.dispose();
		check("span templates contain supported CSS values", Css.problems.length == 0, Css.problems);
	}
}
