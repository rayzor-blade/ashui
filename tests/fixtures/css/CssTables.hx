import ashui.css.Css;
import ashui.css.Identity;
import ashui.layout.LayoutTree;
import ashui.layout.Node;
import ashui.reactive.Owner;
import ashui.reactive.Signal;
import ashui.types.Style;
import ashui.ui.Div;
import ashui.ui.Table.Cell;

/** Table content sizing and mutation: Ashui 8fbda23, CSS/element umbrella 8780d6b. **/
class CssTables {
	static function check(name:String, ok:Bool, ?detail:Dynamic) {
		if (!ok) {
			if (detail != null) Sys.println(Std.string(detail));
			throw name;
		}
		Sys.println('ok   $name');
	}
	static function near(a:Float, b:Float):Bool return Math.abs(a - b) < 1.5;
	static function node(tree:LayoutTree, id:String):Node return new Node(Css.query(tree, tree.root.id, "#" + id)[0]);
	static function box(tree:LayoutTree, id:String) return tree.getBounds(node(tree, id));
	static function settle(tree:LayoutTree, root:Div, width = 600) {
		tree.flush();
		tree.computeLayout(root.node, width, 900);
	}

	static function main() {
		ashui.theme.ThemeState.init(ashui.theme.themes.DefaultTheme.bundle(), Light);
		var tree = new LayoutTree(), text = Signal.make("Inventory"), extra = Signal.make(false);
		var extraText = Signal.make("A wider name");
		var dispose:Void->Void = null;
		var root:Div = Owner.root(tree, stop -> {
			dispose = stop;
			return <div width={600} height={900} flexDirection={Column}>
				<table id="auto" width={600}>
					<thead><tr><th id="h1">Name</th><th id="h2">Qty</th><th id="h3">Price</th></tr></thead>
					<tbody>
						<tr><td id="a1">{text}</td><td id="a2">3</td><td id="a3">1.20</td></tr>
						<tr><td id="span" colspan={2}>spans two</td><td id="last">x</td></tr>
						<if {extra}><tr><td id="extra1">{extraText}</td><td>20</td><td>4.50</td></tr></if>
					</tbody>
				</table>
				<table id="narrow" width={300}>
					<tbody><tr><td id="word">Incomprehensibilities</td><td id="wrapped">a run of words long enough that it has to wrap in what is left</td></tr></tbody>
				</table>
				<table id="given" width={400}>
					<colgroup><col width="120" /><col width="25%" /><col width="2*" /><col width="1*" /></colgroup>
					<tbody><tr><td id="px">a</td><td id="pct">b</td><td id="two">c</td><td id="one">d</td></tr></tbody>
				</table>
				<table id="mixed" width={400}>
					<colgroup><col /><col width="1*" /></colgroup>
					<tbody><tr><td id="sized">short</td><td id="share">long enough to take the remaining space</td></tr></tbody>
				</table>
			</div>;
		});
		settle(tree, root);
		var h1 = box(tree, "h1"), h2 = box(tree, "h2"), h3 = box(tree, "h3");
		var a1 = box(tree, "a1"), a2 = box(tree, "a2"), a3 = box(tree, "a3");
		check("automatic columns reflect their cell content instead of equal shares", a1.width > a2.width * 1.5, [a1.width, a2.width, a3.width]);
		check("headers and body share content sized columns", near(h1.width, a1.width) && near(h2.x, a2.x) && near(h3.width, a3.width));
		var span = box(tree, "span");
		check("colspan covers its tracks and the following cell stays aligned", near(span.width, a1.width + a2.width) && near(box(tree, "last").x, a3.x));
		var word = box(tree, "word"), wrapped = box(tree, "wrapped");
		var narrowHeight = box(tree, "narrow").height;
		check("an unbreakable word holds its column open while the other wraps", word.width >= Cell.at(node(tree, "word").id).flow.widths().min
			&& wrapped.height > 80 && near(word.width + wrapped.width, box(tree, "narrow").width - 2), [word, wrapped]);
		settle(tree, root);
		check("wrapped table height settles within one computeLayout", near(box(tree, "narrow").height, narrowHeight), [narrowHeight, box(tree, "narrow").height]);
		var px = box(tree, "px"), pct = box(tree, "pct"), two = box(tree, "two"), one = box(tree, "one");
		check("explicit pixel percentage and star columns retain their widths", near(px.width, 120) && near(pct.width, 99.5) && near(two.width, 2 * one.width), [px.width, pct.width, two.width, one.width]);
		var sized = box(tree, "sized");
		check("automatic columns take their one-line width beside star columns", near(sized.width, Cell.at(node(tree, "sized").id).flow.widths().max)
			&& box(tree, "share").width > sized.width * 2, [sized.width, box(tree, "share").width]);

		var before = a1.width;
		text.set("Incomprehensibilities");
		settle(tree, root);
		check("reactive text resizes all rows' columns in one layout", box(tree, "a1").width > before + 20 && near(box(tree, "a1").width, box(tree, "h1").width));
		text.set("x");
		settle(tree, root);
		check("shorter text releases its column width", box(tree, "a1").width < before);
		extra.set(true);
		settle(tree, root);
		check("a new row receives the common template and resizes its columns", near(box(tree, "extra1").width, box(tree, "h1").width)
			&& box(tree, "h1").width > before);
		extra.set(false);
		settle(tree, root);
		check("removing the widest row releases its content measurement", box(tree, "h1").width < before);
		extraText.set("x");
		extra.set(true);
		settle(tree, root);
		check("a new row receives columns even when the template is unchanged", near(box(tree, "extra1").width, box(tree, "h1").width));
		extra.set(false);
		settle(tree, root);

		var head = node(tree, "h1"), identity = Identity.of(tree, head.id);
		var beforeFont = box(tree, "h1").width;
		identity.setInline("font-size", "32px");
		settle(tree, root);
		check("font changes invalidate cached column measurements", box(tree, "h1").width > beforeFont + 20);
		identity.setInline("font-size", null);
		settle(tree, root);
		var flow = Cell.at(head.id).flow, widths = flow.widths(), beforeMin = widths.min;
		identity.setInline("padding", "8px 31.5px 8px 7.25px");
		identity.setInline("border-left", "2.5px solid red");
		identity.setInline("border-right", "4.25px solid red");
		settle(tree, root);
		check("asymmetric fractional padding and borders enter intrinsic width", near(flow.widths().min - beforeMin, 21.5), [beforeMin, flow.widths().min]);

		var updates = 0;
		var stop = flow.onWidthsChanged(() -> updates++);
		settle(tree, root);
		settle(tree, root);
		check("unchanged layout reuses measurements without scheduling another frame", updates == 0 && !tree.flush(), updates);
		stop();
		node(tree, "narrow").set(ashui.layout.Prop.Width, 450);
		settle(tree, root);
		check("width only resize redistributes tracks and reduces wrapping", box(tree, "wrapped").height < wrapped.height, [wrapped.height, box(tree, "wrapped").height]);
		dispose();
		check("table measurement callbacks are released with their owner", @:privateAccess !ashui.text.InlineFlow.measured.exists(tree));
		tree.dispose();
		check("table styling reports no unsupported values", Css.problems.length == 0, Css.problems);
	}
}
