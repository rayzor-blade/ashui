import ashui.css.Css;
import ashui.css.Identity;
import ashui.input.Interaction;
import ashui.input.Pointer;
import ashui.layout.LayoutTree;
import ashui.layout.Node;
import ashui.layout.Prop;
import ashui.reactive.Owner;
import ashui.reactive.Signal;
import ashui.types.Style;
import ashui.ui.Div;

/** Row placement, authored ancestry and lifecycle: 471d54e / 8780d6b, ABI bcec1a0. **/
class TableRowSpans {
	static function check(name:String, ok:Bool, ?detail:Dynamic) {
		if (!ok) {
			if (detail != null) Sys.println(Std.string(detail));
			throw name;
		}
		Sys.println('ok   $name');
	}
	static function node(tree:LayoutTree, id:String):Node return Identity.of(tree, Css.query(tree, tree.root.id, "#" + id)[0]).node;
	static function box(tree:LayoutTree, id:String) return tree.getBounds(node(tree, id));
	static function near(a:Float, b:Float):Bool return Math.abs(a - b) < 1.5;
	static function settle(tree:LayoutTree, root:Div) {
		tree.flush();
		tree.computeLayout(root.node, 640, 1800);
	}
	static function main() {
		ashui.theme.ThemeState.init(ashui.theme.themes.DefaultTheme.bundle(), Light);
		var tree = new LayoutTree(), extra = Signal.make(false), text = Signal.make("West");
		var shown = Signal.make(Display.Grid);
		var clicks = 0, lowerClicks = 0, dispose:Void->Void = null;
		var root:Div = Owner.root(tree, stop -> {
			dispose = stop;
			return <div width={640} height={1800} flexDirection={Column}>
				<table id="two" width={600}>
					<caption>Shared row grid</caption>
					<thead><tr><th id="h0">Region</th><th id="h1">Product</th><th id="h2">Count</th></tr></thead>
					<tbody id="body">
						<tr id="r0" display={shown} onClick={_ -> clicks++}><td rowspan={2} id="tall" minHeight={100}>{text}</td><td id="a">Pears</td><td>3</td></tr>
						<tr id="r1" onClick={_ -> lowerClicks++}><td id="b">Apples</td><td>8</td></tr>
						<tr id="r2"><td id="released">East</td><td>Plums</td><td>2</td></tr>
					</tbody>
				</table>
				<table width={600}>
					<tbody>
						<tr id="m0"><td rowspan={3} colspan={2} id="both">Two columns and three rows</td><td id="m02">A</td><td id="m03">B</td></tr>
						<tr id="m1"><td colspan={2} id="wide">A pair in the free columns</td></tr>
						<tr id="m2"><td id="m22">C</td><td>D</td></tr>
						<tr><td id="m30">Back in column one</td><td>2</td><td>3</td><td>4</td></tr>
					</tbody>
				</table>
				<table width={600}>
					<thead><tr><th rowspan={99} id="headClamp">Header</th><th>x</th></tr></thead>
					<tbody id="zeroBody">
						<tr id="z0"><td rowspan={0} id="zero">All remaining rows</td><td id="z01">1</td></tr>
						<tr id="z1"><td id="z11">2</td></tr>
						<if {extra}><tr id="z2"><td id="z21">3</td></tr></if>
					</tbody>
					<tbody><tr id="nextGroup"><td id="nextCell">New group</td><td>x</td></tr></tbody>
					<tfoot><tr><td id="foot">Footer</td><td>x</td></tr></tfoot>
				</table>
				<table id="direct" width={500}>
					<caption>Direct rows</caption>
					<colgroup><col width="80.5" /><col width="25%" /><col width="1*" /></colgroup>
					<tr id="d0"><th id="directSpan" rowspan={2}>Direct</th><td id="percent">1</td><td>2</td></tr>
					<tr id="d1"><td id="percent2">3</td><td>4</td></tr>
				</table>
				<table width={500}><tbody>
					<tr id="e0"><td rowspan={2} id="emptySpan" minHeight={80}>An empty following row</td></tr>
					<tr id="e1" />
					<tr><td rowspan={-3} id="invalid">Invalid span defaults to one</td></tr>
				</tbody></table>
				<table width={500}><tbody>
					<tr><td>1</td><td rowspan={2} id="middle">Middle</td><td id="right">3</td></tr>
					<tr><td colspan={2} id="skipMiddle">Requires two consecutive free columns</td></tr>
				</tbody></table>
				<div display={Grid} width={400} gridTemplateColumns="100px 100px 100px"><td id="standalone" colspan={2} /><td /></div>
			</div>;
		});
		settle(tree, root);
		var tall = box(tree, "tall"), r0 = box(tree, "r0"), r1 = box(tree, "r1");
		check("rowspan spans the two shared row tracks", near(tall.y, r0.y) && near(tall.height, r0.height + r1.height) && tall.height >= 99, [tall, r0, r1]);
		check("a later row skips the occupied column", near(box(tree, "a").x, box(tree, "b").x) && box(tree, "b").x > tall.x);
		check("columns align across header and spanning body groups", near(box(tree, "h1").x, box(tree, "a").x));
		check("a column is available again after a span ends", near(box(tree, "released").x, tall.x));
		var both = box(tree, "both"), m0 = box(tree, "m0"), m1 = box(tree, "m1"), m2 = box(tree, "m2");
		check("rowspan and colspan share one rectangular grid area", near(both.height, m0.height + m1.height + m2.height)
			&& near(box(tree, "wide").x, box(tree, "m02").x) && near(box(tree, "m22").x, box(tree, "wide").x));
		check("combined spans release their reserved columns", near(box(tree, "m30").x, both.x));
		check("a colspan skips an occupied column inside its candidate range", near(box(tree, "skipMiddle").x, box(tree, "right").x));
		check("standalone grid cells retain their colspan behavior", near(box(tree, "standalone").width, 200));
		check("rowspan zero reaches the group's last row", near(box(tree, "zero").height, box(tree, "z0").height + box(tree, "z1").height));
		check("row spans cannot cross section boundaries", near(box(tree, "nextCell").x, box(tree, "zero").x)
			&& box(tree, "headClamp").height < box(tree, "zero").height && near(box(tree, "foot").x, box(tree, "zero").x));
		check("direct rows span beneath a caption without reparenting", near(box(tree, "directSpan").height, box(tree, "d0").height + box(tree, "d1").height)
			&& near(box(tree, "percent").x, box(tree, "percent2").x));
		check("fractional explicit tracks retain their precision", near(box(tree, "directSpan").width, 80.5) && near(box(tree, "percent").width, 124.5));
		check("spans support a following empty row", near(box(tree, "emptySpan").height, box(tree, "e0").height + box(tree, "e1").height));
		check("negative row spans default to one", box(tree, "invalid").height < box(tree, "emptySpan").height);
		check("spanning cells retain their authored row parent", tree.ancestors(node(tree, "tall").id)[0] == node(tree, "r0").id
			&& Css.query(tree, root.node.id, "#r0 > td").indexOf(node(tree, "tall").id) >= 0);
		var order = tree.order();
		check("document and focus traversal retain authored order", order.indexOf(node(tree, "tall").id) < order.indexOf(node(tree, "a").id)
			&& order.indexOf(node(tree, "a").id) < order.indexOf(node(tree, "b").id));
		Pointer.move(tree, tall.x + 8, r1.y + r1.height / 2);
		Pointer.press(tree); Pointer.release(tree);
		check("the lower portion of a span bubbles to its original row", clicks == 1 && lowerClicks == 0);
		check("hover follows the spanning cell's authored row", Interaction.of(node(tree, "r0")).hovered.get()
			&& !Interaction.of(node(tree, "r1")).hovered.get());
		Pointer.leave(tree);
		var height = box(tree, "two").height;
		settle(tree, root);
		check("rowspan layout settles within one compute", near(box(tree, "two").height, height));
		extra.set(true); settle(tree, root);
		check("rowspan zero grows with an added row", near(box(tree, "zero").height,
			box(tree, "z0").height + box(tree, "z1").height + box(tree, "z2").height));
		extra.set(false); settle(tree, root);
		check("removing a row shrinks the spanning grid", near(box(tree, "zero").height, box(tree, "z0").height + box(tree, "z1").height));
		shown.set(Display.None); settle(tree, root);
		check("hidden rows release their reserved columns", near(box(tree, "b").x, box(tree, "released").x));
		shown.set(Display.Grid); settle(tree, root);
		check("showing a row restores its spanning grid", near(box(tree, "a").x, box(tree, "b").x));
		Identity.of(tree, node(tree, "tall").id).setInline("display", "none"); settle(tree, root);
		check("hidden spanning cells release their occupied slots", near(box(tree, "b").x, box(tree, "released").x));
		Identity.of(tree, node(tree, "tall").id).setInline("display", null); settle(tree, root);
		node(tree, "tall").set(Prop.Display, Display.None); settle(tree, root);
		check("a typed display write releases the cell's slot", near(box(tree, "b").x, box(tree, "released").x));
		node(tree, "tall").set(Prop.Display, Display.Flex); settle(tree, root);
		check("a typed display write restores its spanning cell", near(box(tree, "a").x, box(tree, "b").x));
		Identity.of(tree, node(tree, "body").id).setInline("display", "none"); settle(tree, root);
		check("a hidden row group has no visible span hits", tree.hitTest(tall.x + 8, tall.y + 8).length == 0
			|| !Lambda.exists(tree.hitTest(tall.x + 8, tall.y + 8), hit -> hit.id == node(tree, "tall").id));
		Identity.of(tree, node(tree, "body").id).setInline("display", null); settle(tree, root);
		check("showing a row group restores shared row heights", near(box(tree, "tall").height, box(tree, "r0").height + box(tree, "r1").height));
		var before = box(tree, "tall").width;
		text.set("Incomprehensibilities"); settle(tree, root);
		check("reactive spanning text still sizes automatic columns", box(tree, "tall").width > before + 30);
		node(tree, "direct").set(Prop.Width, 600); settle(tree, root);
		check("shared row grids resize percentage tracks", near(box(tree, "percent").width, 149.5) && near(box(tree, "percent").x, box(tree, "percent2").x));
		settle(tree, root); settle(tree, root);
		check("settled row spans do not schedule idle frames", !tree.flush());
		var hooks = Node.displayHooks.length, flushes = LayoutTree.flushHooks.length;
		dispose();
		check("table visibility and layout subscriptions leave with their owner", Node.displayHooks.length < hooks && LayoutTree.flushHooks.length < flushes
			&& @:privateAccess !ashui.text.InlineFlow.measured.exists(tree));
		tree.dispose();
		check("rowspan templates are accepted by the cascade", Css.problems.length == 0, Css.problems);
	}
}
