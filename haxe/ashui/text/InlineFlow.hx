package ashui.text;

import ashui.core.externs.TextNative;
import ashui.css.Identity;
import ashui.layout.AfterChildren;
import ashui.layout.LayoutTree;
import ashui.layout.Node;
import ashui.layout.Prop;
import ashui.reactive.Owner;
import ashui.reactive.Signal;
import ashui.reactive.Watch;
import ashui.types.Style;
import ashui.ui.Div;
import ashui.ui.Text;

/** A run of text in a flow: one `Text`, its whitespace collapsed, and where each of its characters ends. **/
private class Run {
	public final probe:Text;
	/** The node its pieces are placed under: the flow's root or an inline element in it. **/
	public final parent:haxe.Int64;
	public var text = "";
	/** The x at each string index of `text`, its end included. **/
	public var stops:Array<Float> = [0];
	/** From a piece's top to its baseline, and from the baseline to its bottom. **/
	public var above = 0.0;
	public var below = 0.0;
	/** The pieces shown, made as lines need them and kept for the next flow. **/
	public final pieces:Array<Piece> = [];

	public function new(probe:Text, parent:haxe.Int64) {
		this.probe = probe;
		this.parent = parent;
	}

	public inline function x(i:Int):Float
		return stops[i < stops.length ? i : stops.length - 1];
}

/** One line's part of a run, a text that does not wrap, placed where the line puts it. **/
private class Piece {
	public final text:Text;
	public final content = Signal.make("");
	public final left = Signal.make((0 : Single));
	public final top = Signal.make((0 : Single));
	public final shown = Signal.make(Display.None);

	public function new(tree:LayoutTree) {
		text = new Text(content, {wrap: false}, tree);
		text.node.set(Prop.Position, Position.Absolute);
		text.node.set(Prop.Left, left);
		text.node.set(Prop.Top, top);
		text.node.set(Prop.Display, shown);
	}
}

/** An inline element kept whole, as one that paints a box is, or an element that is not inline: placed as a box, by its laid-out size. **/
private class Atom {
	public final node:Node;
	public final left = Signal.make((0 : Single));
	public final top = Signal.make((0 : Single));
	public var width = 0.0;
	public var height = 0.0;
	/** From its top to its baseline: its first text's, or its bottom. **/
	public var above = 0.0;
	/** A block, as a list in an item is: on a line of its own, as wide as the flow. **/
	public final block:Bool;
	public final fill = Signal.make((0 : Single));

	public function new(node:Node, block:Bool) {
		this.node = node;
		this.block = block;
		node.set(Prop.Position, Position.Absolute);
		node.set(Prop.Left, left);
		node.set(Prop.Top, top);
		if (block)
			node.set(Prop.Width, fill);
	}
}

/** What a flow lays out, in order. **/
private enum Item {
	/** A word of a run, `start` to `end`, and the width of the space after it, 0 if none; a word may be empty, holding a space alone. **/
	Word(run:Run, start:Int, end:Int, width:Float, space:Float);
	Box(atom:Atom);
	Break;
}

private typedef Line = {
	var items:Array<{item:Item, x:Float}>;
	var above:Float;
	var below:Float;
}

/**
	HTML's inline formatting: a paragraph's text and the inline elements in
	it laid out as one flow, wrapped together at the paragraph's width, each
	line's pieces on one baseline whatever their font. Whitespace collapses
	as HTML's does: a run of it is one space, and none starts or ends a line.

	A paragraph, a heading and the other elements that hold text are flows
	(hxx makes them so; see `attach`). The elements in one keep their place
	in the tree, so CSS styles them and they take input as before; only how
	they are laid out changes:

	- each `Text` is measured in its own font and hidden, and what each line
	  shows of it is a piece, a text that does not wrap, placed under the
	  same element so it is styled as the text is;
	- an inline element that paints nothing of its own (`a`, `strong`, `em`)
	  is a frame its pieces are placed in, so its text wraps freely and a
	  click on any of it is a click on it;
	- an inline element that paints a box (`code`'s background, `mark`'s),
	  and anything that is not inline (an `img`, an `input`), is kept whole
	  and placed as a box by its laid-out size, on its first text's baseline.

	The flow's size comes from one box laid out in its place: as wide as its
	longest line can be, no narrower than its longest word, and as tall as
	its lines at the width it is given. After a layout pass it lays the lines
	out again at that width, and asks for another pass when anything moved.
**/
class InlineFlow {
	/** HTML's inline elements that ashui builds in. **/
	public static final INLINE = [
		"span", "strong", "b", "em", "i", "small", "code", "kbd", "mark", "s", "u", "a", "output", "sub", "sup", "abbr", "cite", "q", "time", "var", "samp",
		"del", "ins", "label"
	];

	/** HTML's block elements: in a flow, each starts a line of its own and ends it. **/
	public static final BLOCK = [
		"div", "p", "h1", "h2", "h3", "h4", "h5", "h6", "ul", "ol", "dl", "table", "pre", "blockquote", "figure", "details", "fieldset", "hr", "form"
	];

	static final flows = new haxe.ds.ObjectMap<LayoutTree, Array<InlineFlow>>();
	static final byMember = new Map<String, InlineFlow>();
	static var hooked = false;

	final root:Div;
	final tree:LayoutTree;
	/** Laid out in the flow's place, sized to its lines, so the root sizes itself around them. **/
	final spacer:Div;
	/** At the origin absolute positions are measured from, so pieces can be placed against the spacer. **/
	final anchor:Div;
	final spacerWidth = Signal.make((0 : Single));
	final spacerMin = Signal.make((0 : Single));
	final spacerHeight = Signal.make((0 : Single));

	var runs:Array<Run> = [];
	var atoms:Array<Atom> = [];
	var order:Array<Item> = [];
	var members:Array<String> = [];
	var watches:Array<Watch<String>> = [];
	final kept = new Map<String, Run>();
	final keptAtoms = new Map<String, Atom>();
	final framed = new Map<String, Bool>();

	var structureChanged = true;
	var measureChanged = true;
	var flowedWidth = -1.0;
	var placed = "";

	/** Makes `root` a flow; its children are its inline content. **/
	public static function attach(root:Div):InlineFlow {
		hook();
		var flow = new InlineFlow(root);
		var list = flows.get(root.tree);
		if (list == null)
			flows.set(root.tree, list = []);
		list.push(flow);
		var tree = root.tree;
		Owner.onCleanup(() -> {
			var l = flows.get(tree);
			if (l != null)
				l.remove(flow);
			flow.forget();
		});
		return flow;
	}

	function new(root:Div) {
		this.root = root;
		tree = root.tree;
		anchor = new Div({position: Absolute, left: 0, top: 0, width: 0, height: 0}, tree);
		spacer = new Div({
			width: spacerWidth,
			minWidth: spacerMin,
			height: spacerHeight,
			flexShrink: 1
		}, tree);
		spacer.node.set(Prop.MaxWidthPercent, 1);
		// First, so they are under everything for the hit test: the spacer covers the flow.
		tree.replaceChildren(root.node.id, [anchor.node.id, spacer.node.id].concat(tree.children(root.node.id)));
		var key = haxe.Int64.toStr(root.node.id);
		AfterChildren.watch(tree, "flow " + key, parent -> parent == root.node.id || members.indexOf(haxe.Int64.toStr(parent)) >= 0, () -> structureChanged = true);
	}

	function forget():Void {
		for (m in members)
			byMember.remove(m);
		for (w in watches)
			w.stop();
	}

	static function hook():Void {
		if (hooked)
			return;
		hooked = true;
		LayoutTree.layoutHooks.push(tree -> {
			var list = flows.get(tree);
			var changed = false;
			if (list != null)
				for (flow in list.copy())
					if (flow.layOut())
						changed = true;
			changed;
		});
		ashui.css.Css.restyled.push(identity -> {
			var flow = byMember.get(haxe.Int64.toStr(identity.node.id));
			if (flow != null)
				flow.measureChanged = true;
		});
	}

	static inline function key(id:haxe.Int64):String
		return haxe.Int64.toStr(id);

	function isInline(identity:Null<Identity>):Bool
		return identity != null && Lambda.exists(identity.types, t -> INLINE.indexOf(t) >= 0);

	/** The flow's content, in order: runs, frames and boxes, read from the tree. **/
	function collect():Void {
		for (m in members)
			byMember.remove(m);
		for (w in watches)
			w.stop();
		watches = [];
		members = [key(root.node.id)];
		var seen = new Map<String, Bool>();
		var nextRuns = [], nextAtoms = [];
		order = [];
		var skip = [key(anchor.node.id) => true, key(spacer.node.id) => true];
		for (r in kept)
			for (p in r.pieces)
				skip.set(key(p.text.node.id), true);
		function walk(parent:haxe.Int64) {
			for (child in tree.children(parent)) {
				var k = key(child);
				if (skip.exists(k))
					continue;
				var text = Text.at(child);
				if (text != null) {
					var run = kept.get(k);
					if (run == null || run.parent != parent) {
						run = new Run(text, parent);
						text.node.set(Prop.Display, Display.None);
						kept.set(k, run);
					}
					seen.set(k, true);
					nextRuns.push(run);
					order.push(Word(run, 0, 0, 0, 0));
					members.push(k);
					watches.push(new Watch(() -> text.text(), _ -> measureChanged = true));
					continue;
				}
				var identity = Identity.of(tree, child);
				if (identity != null && identity.types.indexOf("br") >= 0) {
					order.push(Break);
					continue;
				}
				var edges = tree.boxEdges(child);
				var plain = isInline(identity) && edges != null && !edges.painted && edges.top + edges.right + edges.bottom + edges.left == 0;
				if (plain) {
					// A frame: at the origin, its pieces placed in it.
					if (!framed.exists(k)) {
						var n = new Node(child);
						n.set(Prop.Position, Position.Absolute);
						n.set(Prop.Left, 0);
						n.set(Prop.Top, 0);
						framed.set(k, true);
					}
					members.push(k);
					walk(child);
					continue;
				}
				var atom = keptAtoms.get(k);
				if (atom == null) {
					atom = new Atom(new Node(child), identity != null && Lambda.exists(identity.types, t -> BLOCK.indexOf(t) >= 0));
					keptAtoms.set(k, atom);
				}
				seen.set(k, true);
				nextAtoms.push(atom);
				order.push(Box(atom));
				members.push(k);
			}
		}
		walk(root.node.id);
		// Runs that left the flow: their pieces go with them.
		for (k => run in kept)
			if (!seen.exists(k)) {
				for (p in run.pieces)
					p.text.remove();
				kept.remove(k);
			}
		for (k => _ in keptAtoms)
			if (!seen.exists(k))
				keptAtoms.remove(k);
		runs = nextRuns;
		atoms = nextAtoms;
		for (m in members)
			byMember.set(m, this);
	}

	/** Each run's collapsed text, measured in its font. **/
	function measure():Void {
		// A space after a space, or at the start, collapses away.
		var afterSpace = true;
		for (item in order)
			switch item {
				case Word(run, _, _, _, _):
					var s = ~/[ \t\r\n\x0C]+/g.replace(run.probe.text(), " ");
					if (afterSpace && StringTools.startsWith(s, " "))
						s = s.substr(1);
					if (s.length > 0)
						afterSpace = StringTools.endsWith(s, " ");
					run.text = s;
					shape(run);
				case Box(_):
					afterSpace = false;
				case Break:
					afterSpace = true;
			}
		for (atom in atoms) {
			var b = tree.getBounds(atom.node);
			atom.width = b == null ? 0 : b.width;
			atom.height = b == null ? 0 : b.height;
			atom.above = baselineOf(atom);
		}
	}

	static final out = new hl.Bytes(4096 * 12);
	static final info = new hl.Bytes(16);

	function shape(run:Run):Void {
		var s = run.text;
		var capacity = s.length + 2;
		var bytes = capacity <= 4096 ? out : new hl.Bytes(capacity * 12);
		var n = TextNative.blinc_text_carets(tree.ptr, run.probe.node.id, ashui.core.Utf8.encode(s), 0, 0, bytes, capacity, info);
		var stops = [for (_ in 0...s.length + 1) 0.0];
		var at = 0, last = 0.0;
		for (i in 0...Std.int(Math.min(n, capacity))) {
			var index = Std.int(bytes.getF32(i * 12));
			var x = bytes.getF32(i * 12 + 4);
			// Indices inside a character, the second half of a surrogate pair, stand where it starts.
			while (at < index && at <= s.length)
				stops[at++] = last;
			if (index <= s.length)
				stops[index] = x;
			last = x;
			at = index + 1;
		}
		while (at <= s.length)
			stops[at++] = last;
		run.stops = stops;
		if (n > 0) {
			var lineHeight = info.getF32(0), ascender = info.getF32(8), descender = info.getF32(12);
			// As the text is drawn: half the leading above the ascender.
			run.above = (lineHeight - (ascender - descender)) / 2 + ascender;
			run.below = lineHeight - run.above;
		}
	}

	/** From `atom`'s top to its baseline: its first text's, inside its padding, or its bottom. **/
	function baselineOf(atom:Atom):Float {
		var edges = tree.boxEdges(atom.node.id);
		for (child in tree.children(atom.node.id)) {
			var text = Text.at(child);
			if (text == null)
				continue;
			var b = tree.getBounds(text.node), a = tree.getBounds(atom.node);
			var bytes = new hl.Bytes(12 * 4);
			if (b == null || a == null || TextNative.blinc_text_carets(tree.ptr, text.node.id, ashui.core.Utf8.encode("x"), 0, 0, bytes, 4, info) == 0)
				break;
			var lineHeight = info.getF32(0), ascender = info.getF32(8), descender = info.getF32(12);
			return b.y - a.y + (lineHeight - (ascender - descender)) / 2 + ascender;
		}
		return atom.height;
	}

	/** The words of each run, between the boxes and breaks. **/
	function items():Array<Item> {
		var list = [];
		for (item in order)
			switch item {
				case Word(run, _, _, _, _):
					var s = run.text;
					var i = 0;
					while (i < s.length) {
						var end = s.indexOf(" ", i);
						if (end < 0)
							end = s.length;
						var space = end < s.length ? run.x(end + 1) - run.x(end) : 0.0;
						list.push(Word(run, i, end, run.x(end) - run.x(i), space));
						i = end + 1;
					}
				case other:
					list.push(other);
			}
		return list;
	}

	/** Lines of `list` at `width`: greedy, breaking at spaces, a space at the start of a line dropped. **/
	function lines(list:Array<Item>, width:Float):Array<Line> {
		var out:Array<Line> = [];
		var line:Line = {items: [], above: 0, below: 0};
		var x = 0.0;
		function end() {
			out.push(line);
			line = {items: [], above: 0, below: 0};
			x = 0;
		}
		for (item in list) {
			var w = switch item {
				case Word(_, _, _, w, _): w;
				case Box(atom): atom.width;
				case Break: 0.0;
			}
			switch item {
				case Break:
					end();
					continue;
				case Word(_, _, _, w, _) if (w == 0 && x == 0):
					// A space alone at the start of a line.
					continue;
				case _:
			}
			var block = switch item {
				case Box(atom): atom.block;
				case _: false;
			}
			if ((x > 0 && x + w > width + 0.01) || (block && line.items.length > 0))
				end();
			line.items.push({item: item, x: x});
			if (block) {
				end();
				continue;
			}
			x += w + switch item {
				case Word(_, _, _, _, space): space;
				case _: 0.0;
			};
		}
		if (line.items.length > 0 || out.length == 0)
			out.push(line);
		for (l in out)
			for (p in l.items)
				switch p.item {
					case Word(run, _, _, _, _):
						l.above = Math.max(l.above, run.above);
						l.below = Math.max(l.below, run.below);
					case Box(atom):
						l.above = Math.max(l.above, atom.above);
						l.below = Math.max(l.below, atom.height - atom.above);
					case Break:
				}
		// An empty line is as tall as the text around it.
		var strut = runs.length > 0 ? runs[0] : null;
		for (l in out)
			if (l.above + l.below == 0 && strut != null) {
				l.above = strut.above;
				l.below = strut.below;
			}
		return out;
	}

	/** After a layout pass: lays the lines out at the width given, and says whether anything moved. **/
	function layOut():Bool {
		if (tree.getBounds(spacer.node) == null)
			return false;
		var changed = false;
		if (structureChanged) {
			collect();
			structureChanged = false;
			measureChanged = true;
			changed = true;
		}
		if (measureChanged) {
			measure();
			measureChanged = false;
			flowedWidth = -1;
			var list = items();
			// As wide as the longest line can be, no narrower than the longest word.
			var longest = 0.0, widest = 0.0, x = 0.0, trailing = 0.0;
			for (item in list)
				switch item {
					case Word(_, _, _, w, space):
						widest = Math.max(widest, w);
						x += w + space;
						trailing = space;
					case Box(atom) if (atom.block):
						// A block takes the flow's width, whatever that is; it sets none.
						longest = Math.max(longest, x - trailing);
						x = trailing = 0;
					case Box(atom):
						widest = Math.max(widest, atom.width);
						x += atom.width;
						trailing = 0;
					case Break:
						longest = Math.max(longest, x - trailing);
						x = trailing = 0;
				}
			longest = Math.max(longest, x - trailing);
			changed = set(spacerWidth, Math.ceil(longest)) || changed;
			changed = set(spacerMin, Math.ceil(widest)) || changed;
		}
		var s = tree.getBounds(spacer.node), a = tree.getBounds(anchor.node);
		if (s == null || a == null)
			return changed;
		for (atom in atoms)
			if (atom.block)
				changed = set(atom.fill, s.width) || changed;
		if (s.width != flowedWidth || changed) {
			flowedWidth = s.width;
			changed = place(lines(items(), s.width), s.x - a.x, s.y - a.y) || changed;
		}
		return changed;
	}

	static function set(signal:Signal<Single>, v:Float):Bool {
		if (signal.get() == v)
			return false;
		signal.set(v);
		return true;
	}

	/** Puts each line's pieces and boxes in place, from `(dx, dy)`; true when anything moved. **/
	function place(lines:Array<Line>, dx:Float, dy:Float):Bool {
		var used = new Map<Run, Int>();
		var sig = new StringBuf();
		var y = 0.0;
		for (line in lines) {
			var i = 0;
			while (i < line.items.length) {
				var p = line.items[i];
				switch p.item {
					case Word(run, start, _, _, _):
						// The run's words on this line, one piece.
						var j = i, end = 0;
						while (j < line.items.length)
							switch line.items[j].item {
								case Word(r, _, e, _, _) if (r == run):
									end = e;
									j++;
								case _:
									break;
							}
						var n = used.exists(run) ? used.get(run) : 0;
						used.set(run, n + 1);
						if (n >= run.pieces.length) {
							var piece = Owner.root(tree, _ -> new Piece(tree));
							tree.addChild(run.parent, piece.text.node.id);
							run.pieces.push(piece);
						}
						var piece = run.pieces[n];
						var text = run.text.substring(start, end);
						var left = dx + p.x, top = dy + y + line.above - run.above;
						piece.content.set(text);
						set(piece.left, left);
						set(piece.top, top);
						piece.shown.set(Display.Flex);
						sig.add('$text@$left,$top;');
						i = j;
					case Box(atom):
						var left = dx + p.x, top = dy + y + line.above - atom.above;
						set(atom.left, left);
						set(atom.top, top);
						sig.add('box@$left,$top;');
						i++;
					case Break:
						i++;
				}
			}
			y += line.above + line.below;
		}
		// Pieces no line needs now are hidden, kept for later.
		for (run in runs) {
			var n = used.exists(run) ? used.get(run) : 0;
			for (k in n...run.pieces.length)
				run.pieces[k].shown.set(Display.None);
		}
		var heightChanged = set(spacerHeight, Math.ceil(y));
		var s = sig.toString();
		var moved = s != placed;
		placed = s;
		return moved || heightChanged;
	}
}
