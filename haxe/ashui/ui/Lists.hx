package ashui.ui;

import ashui.layout.Element;
import ashui.layout.IntoReactive;
import ashui.layout.LayoutTree;
import ashui.reactive.Owner;

typedef UlProps = {
	?id:String
}

typedef OlProps = {
	/** First item number. Defaults to 1, or the item count for a reversed list. **/
	?start:Int,

	/** Counts downward instead of upward. **/
	?reversed:Bool,

	/** Numbering style: `1` (default), `a`, `A`, `i`, or `I`. **/
	?type:String,

	?id:String
}

/**
	Updates list markers when items change. Also updates nested lists after
	attachment, when their nesting depth is known.
**/
private class Marking {
	static final lists = new Map<String, {tree:LayoutTree, mark:Void->Void}>();

	public static function watch(box:Div, mark:Void->Void):Void {
		var tree = box.tree,
			id = box.node.id,
			key = haxe.Int64.toStr(box.node.id);
		lists.set(key, {tree: tree, mark: mark});
		ashui.layout.AfterChildren.watch(tree, "list " + key, parent -> parent == id, mark);
		Owner.onCleanup(() -> lists.remove(key));
		mark();
	}

	/** Updates nested lists without descending through another list first. **/
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

	/** Returns the number of enclosing lists. **/
	public static function depth(tree:LayoutTree, node:haxe.Int64):Int {
		var n = 0;
		for (up in tree.ancestors(node))
			if (lists.exists(haxe.Int64.toStr(up)))
				n++;
		return n;
	}

	/** Returns the list items directly under a node. **/
	public static function items(tree:LayoutTree, node:haxe.Int64):Array<Li>
		return [for (c in tree.children(node)) if (Li.at(c) != null) Li.at(c)];
}

/**
	A bulleted list, written as `<ul>` in HXX. Nested lists use disc, circle,
	then square bullets by default.
**/
class Ul extends Component<UlProps> {
	static final BULLETS = ["disc", "circle", "square"];

	function render():Element {
		var box = new Div({tag: "ul", id: props.id}, children);
		var tree = box.tree;
		Marking.watch(box, () -> {
			var depth = Std.int(Math.min(Marking.depth(tree, box.node.id), BULLETS.length - 1));
			var items = Marking.items(tree, box.node.id);
			for (i => li in items)
				li.mark(i + 1, BULLETS[depth]);
			Marking.markNested(tree, [for (li in items) li.node.id]);
		});
		return box;
	}
}

/**
	A numbered list, written as `<ol>` in HXX. `start` sets the first number,
	`reversed` counts downward, and `type` selects the numbering style.
	An item `value` overrides its number and the count for later items.
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
				li.mark(n, switch props.type {
					case "a": "lower-alpha";
					case "A": "upper-alpha";
					case "i": "lower-roman";
					case "I": "upper-roman";
					case _: "decimal";
				});
				n += step;
			}
			Marking.markNested(tree, [for (li in items) li.node.id]);
		});
		return box;
	}

	/** Formats a number as decimal digits, letters, or Roman numerals in the selected case. **/
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
