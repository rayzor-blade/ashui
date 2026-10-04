package ashui.ui;

import ashui.layout.Element;
import ashui.layout.IntoReactive;
import ashui.layout.LayoutTree;
import ashui.reactive.Owner;

typedef UlProps = {
	?id:String
}

typedef OlProps = {
	/** The number of its first item; 1, or the count of items when reversed. **/
	?start:Int,

	/** Counts down instead of up. **/
	?reversed:Bool,

	/** How it counts, as HTML's `type`: `1` (the default), `a`, `A`, `i` or `I`. **/
	?type:String,

	?id:String
}

/**
	What `<ul>` and `<ol>` share: they mark their `<li>`s again whenever
	items come or go, and mark the lists nested in them, which know their
	depth only once they are in place.
**/
private class Marking {
	static final lists = new Map<String, {tree:LayoutTree, mark:Void->Void}>();

	public static function watch(box:Div, mark:Void->Void):Void {
		var tree = box.tree, id = box.node.id, key = haxe.Int64.toStr(box.node.id);
		lists.set(key, {tree: tree, mark: mark});
		ashui.layout.AfterChildren.watch(tree, "list " + key, parent -> parent == id, mark);
		Owner.onCleanup(() -> lists.remove(key));
		mark();
	}

	/** Lists inside `items`, not inside another list of them. **/
	public static function markNested(tree:LayoutTree, items:Array<haxe.Int64>):Void {
		var stack = items.copy();
		while (stack.length > 0) {
			var at = stack.pop();
			for (child in tree.children(at)) {
				var list = lists.get(haxe.Int64.toStr(child));
				if (list != null)
					list.mark();
				else
					stack.push(child);
			}
		}
	}

	/** How many lists `node` is inside. **/
	public static function depth(tree:LayoutTree, node:haxe.Int64):Int {
		var n = 0;
		for (up in tree.ancestors(node))
			if (lists.exists(haxe.Int64.toStr(up)))
				n++;
		return n;
	}

	/** The items among `node`'s children. **/
	public static function items(tree:LayoutTree, node:haxe.Int64):Array<Li>
		return [for (c in tree.children(node)) if (Li.at(c) != null) Li.at(c)];
}

/**
	HTML's `<ul>`, built in: a list whose items are marked with a bullet,
	a disc, then a circle in a list inside one, then a square deeper.
**/
class Ul extends Component<UlProps> {
	static final BULLETS = ["disc", "circle", "square"];

	function render():Element {
		var box = new Div({tag: "ul", id: props.id}, children);
		var tree = box.tree;
		Marking.watch(box, () -> {
			var depth = Std.int(Math.min(Marking.depth(tree, box.node.id), BULLETS.length - 1));
			var items = Marking.items(tree, box.node.id);
			for (li in items) {
				li.marker.set(" ");
				li.bullet.set(BULLETS[depth]);
			}
			Marking.markNested(tree, [for (li in items) li.node.id]);
		});
		return box;
	}
}

/**
	HTML's `<ol>`, built in: a list whose items are numbered, from `start`,
	counting down when `reversed`, in the style of `type`; an item's `value`
	sets its number and those after it.
**/
class Ol extends Component<OlProps> {
	function render():Element {
		var box = new Div({tag: "ol", id: props.id}, children);
		var tree = box.tree;
		Marking.watch(box, () -> {
			var items = Marking.items(tree, box.node.id);
			var step = props.reversed == true ? -1 : 1;
			var n = props.start != null ? props.start : props.reversed == true ? items.length : 1;
			for (li in items) {
				if (li.props.value != null)
					n = li.props.value;
				li.marker.set(counter(n, props.type) + ".");
				li.bullet.set("");
				n += step;
			}
			Marking.markNested(tree, [for (li in items) li.node.id]);
		});
		return box;
	}

	/** `n` written as `type` counts: decimal, letters, or roman numerals, in either case. **/
	public static function counter(n:Int, type:Null<String>):String {
		return switch type {
			case "a" | "A" if (n > 0):
				var s = "";
				var k = n;
				while (k > 0) {
					k--;
					s = String.fromCharCode((type == "a" ? 97 : 65) + k % 26) + s;
					k = Std.int(k / 26);
				}
				s;
			case "i" | "I" if (n > 0 && n < 4000):
				var s = "";
				var k = n;
				var values = [1000, 900, 500, 400, 100, 90, 50, 40, 10, 9, 5, 4, 1];
				var symbols = ["M", "CM", "D", "CD", "C", "XC", "L", "XL", "X", "IX", "V", "IV", "I"];
				for (i in 0...values.length)
					while (k >= values[i]) {
						s += symbols[i];
						k -= values[i];
					}
				type == "i" ? s.toLowerCase() : s;
			case _: Std.string(n);
		}
	}
}
