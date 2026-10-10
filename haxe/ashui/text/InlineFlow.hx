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
	/** The inline element that paints a box around it, as `code` does, when it is that element's text. **/
	public var deco:Null<Deco> = null;

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
		Identity.of(tree, text.node.id).anonymous = true;
		text.node.set(Prop.Position, Position.Absolute);
		text.node.set(Prop.Left, left);
		text.node.set(Prop.Top, top);
		text.node.set(Prop.Display, shown);
	}
}

/**
	An inline element that paints a box, as `code`'s background, around one
	text: a box on each line its text is on. The first is the element; those
	after are copies of it, of its type and classes, so CSS styles them
	alike. Its padding is at its start and end, not where a line breaks it,
	as CSS's `box-decoration-break: slice`.
**/
private class Deco {
	public final node:Node;
	public final tag:String;
	public final classes:Array<String>;
	public var padding = {top: 0.0, right: 0.0, bottom: 0.0, left: 0.0};
	public final boxes:Array<DecoBox> = [];

	public function new(node:Node, tag:String, classes:Array<String>) {
		this.node = node;
		this.tag = tag;
		this.classes = classes;
	}
}

/** One line's box of a `Deco`. **/
private class DecoBox {
	public final node:Node;
	public final left = Signal.make((0 : Single));
	public final top = Signal.make((0 : Single));
	public final width = Signal.make((0 : Single));
	public final height = Signal.make((0 : Single));
	public final shown = Signal.make(Display.Flex);

	public function new(node:Node) {
		this.node = node;
		node.set(Prop.Position, Position.Absolute);
		node.set(Prop.Left, left);
		node.set(Prop.Top, top);
		node.set(Prop.Width, width);
		node.set(Prop.Height, height);
		node.set(Prop.Display, shown);
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
	/** The last line of the flow or before a break, which justifying leaves as it is. **/
	var ends:Bool;
}

/** How a flow's lines sit in its width: CSS's `text-align`. **/
private enum abstract Align(Int) {
	var Left = 0;
	var Center = 1;
	var Right = 2;
	var Justify = 3;
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
	final decos = new Map<String, Deco>();

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
		// As wide as its longest line when what holds it sizes to it, as wide as what holds it when that is wider, so lines align across it.
		spacer = new Div({
			width: spacerWidth,
			minWidth: spacerMin,
			height: spacerHeight,
			flexShrink: 1,
			flexGrow: 1
		}, tree);
		spacer.node.set(Prop.MaxWidthPercent, 1);
		Identity.of(tree, anchor.node.id).anonymous = true;
		Identity.of(tree, spacer.node.id).anonymous = true;
		// First, so they are under everything for the hit test: the spacer covers the flow.
		tree.replaceChildren(root.node.id, [anchor.node.id, spacer.node.id].concat(tree.children(root.node.id)));
		// The root's id, kept: taking a flow away removes its nodes before its owner's cleanup stops this watch.
		var rootId = root.node.id;
		var key = haxe.Int64.toStr(rootId);
		AfterChildren.watch(tree, "flow " + key, parent -> parent == rootId || members.indexOf(haxe.Int64.toStr(parent)) >= 0, () -> structureChanged = true);
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
		for (d in decos)
			for (i => b in d.boxes)
				if (i > 0)
					skip.set(key(b.node.id), true);
		var seenDecos = new Map<String, Bool>();
		/** The texts under `node` when they are all it holds, the flow's own pieces aside. **/
		function onlyText(node:haxe.Int64):Null<Array<haxe.Int64>> {
			var texts = [];
			for (c in tree.children(node))
				if (skip.exists(key(c)))
					continue;
				else if (Text.at(c) != null)
					texts.push(c);
				else
					return null;
			return texts;
		}
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
					run.deco = null;
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
				var texts = !plain && isInline(identity) ? onlyText(child) : null;
				if (texts != null && texts.length == 1) {
					// A box around one text: a box on each line it is on.
					var deco = decos.get(k);
					if (deco == null) {
						deco = new Deco(new Node(child), identity.types[0], identity.classes().copy());
						deco.boxes.push(new DecoBox(deco.node));
						decos.set(k, deco);
					}
					seenDecos.set(k, true);
					var t = texts[0], tk = key(t);
					var text = Text.at(t);
					var run = kept.get(tk);
					if (run == null || run.parent != child) {
						run = new Run(text, child);
						text.node.set(Prop.Display, Display.None);
						kept.set(tk, run);
					}
					run.deco = deco;
					seen.set(tk, true);
					nextRuns.push(run);
					order.push(Word(run, 0, 0, 0, 0));
					members.push(k);
					members.push(tk);
					watches.push(new Watch(() -> text.text(), _ -> measureChanged = true));
					continue;
				}
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
		// Boxes that left the flow: their copies go with them.
		for (k => d in decos)
			if (!seenDecos.exists(k)) {
				for (i => b in d.boxes)
					if (i > 0)
						tree.removeSubtree(b.node.id);
				decos.remove(k);
			}
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
		for (d in decos) {
			var e = tree.boxEdges(d.node.id);
			if (e != null)
				d.padding = {top: e.top, right: e.right, bottom: e.bottom, left: e.left};
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
						var w = run.x(end) - run.x(i);
						// A box around the text is wider by its padding at the text's start and end.
						if (run.deco != null) {
							if (i == 0)
								w += run.deco.padding.left;
							if (end == s.length)
								w += run.deco.padding.right;
						}
						list.push(Word(run, i, end, w, space));
						i = end + 1;
					}
				case other:
					list.push(other);
			}
		return list;
	}

	/** Whether a word longer than the line may break inside: CSS's `overflow-wrap: anywhere` or `break-word`, or `word-break: break-all`. **/
	function breaksWords():Bool {
		var identity = Identity.of(tree, root.node.id);
		if (identity == null)
			return false;
		var wrap = ashui.css.Css.computed(identity, "overflow-wrap");
		if (wrap == null)
			wrap = ashui.css.Css.computed(identity, "word-wrap");
		var wordBreak = ashui.css.Css.computed(identity, "word-break");
		return (wrap != null && ["anywhere", "break-word"].indexOf(StringTools.trim(wrap)) >= 0)
			|| (wordBreak != null && ["break-all", "break-word"].indexOf(StringTools.trim(wordBreak)) >= 0);
	}

	/** Lines of `list` at `width`: greedy, breaking at spaces, a space at the start of a line dropped. **/
	function lines(list:Array<Item>, width:Float):Array<Line> {
		var breaking = breaksWords();
		var out:Array<Line> = [];
		var line:Line = {items: [], above: 0, below: 0, ends: false};
		var x = 0.0;
		function end(ends = false) {
			line.ends = ends;
			out.push(line);
			line = {items: [], above: 0, below: 0, ends: false};
			x = 0;
		}
		var queue = list.copy();
		queue.reverse();
		while (queue.length > 0) {
			var item = queue.pop();
			// A word too long for any line, where CSS lets it break: as much as fits in the room left, the rest after.
			switch item {
				case Word(run, start, end, w, space) if (breaking && w > width && run.deco == null && end - start > 1):
					var room = width - x;
					var to = start;
					while (to < end && run.x(to + 1) - run.x(start) <= room)
						to++;
					if (to == start && x == 0)
						to = start + 1;
					if (to > start && to < end) {
						queue.push(Word(run, to, end, run.x(end) - run.x(to), space));
						item = Word(run, start, to, run.x(to) - run.x(start), 0);
					}
				case _:
			}
			var w = switch item {
				case Word(_, _, _, w, _): w;
				case Box(atom): atom.width;
				case Break: 0.0;
			}
			switch item {
				case Break:
					end(true);
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
				end(true);
				continue;
			}
			x += w + switch item {
				case Word(_, _, _, _, space): space;
				case _: 0.0;
			};
		}
		if (line.items.length > 0 || out.length == 0) {
			line.ends = true;
			out.push(line);
		}
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
		// An empty line takes the root's strut, as CSS's: the metrics of text set directly in the root,
		// whose font and line height are the root's own; failing that, the first run's.
		var strut = Lambda.find(runs, r -> r.parent == root.node.id);
		if (strut == null && runs.length > 0)
			strut = runs[0];
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
			// A word that may break sets no minimum: the flow can be as narrow as what holds it.
			changed = set(spacerMin, breaksWords() ? 0 : Math.ceil(widest)) || changed;
		}
		var s = tree.getBounds(spacer.node), a = tree.getBounds(anchor.node);
		if (s == null || a == null)
			return changed;
		for (atom in atoms)
			if (atom.block)
				changed = set(atom.fill, s.width) || changed;
		if (s.width != flowedWidth || changed) {
			flowedWidth = s.width;
			changed = place(lines(items(), s.width), s.x - a.x, s.y - a.y, s.width, alignment()) || changed;
		}
		return changed;
	}

	/** The root's `text-align`: its own, as CSS or Tw set it, or `justify` from the cascade, which a single text cannot draw. **/
	function alignment():Align {
		var identity = Identity.of(tree, root.node.id);
		var css = identity == null ? null : ashui.css.Css.computed(identity, "text-align");
		if (css != null && StringTools.trim(css).toLowerCase() == "justify")
			return Justify;
		return switch tree.textAlign(root.node.id) {
			case 1: Center;
			case 2: Right;
			case _: Left;
		}
	}

	static function itemWidth(item:Item):Float
		return switch item {
			case Word(_, _, _, w, _): w;
			case Box(atom): atom.width;
			case Break: 0.0;
		}

	/** `deco`'s box for its `n`th line: the element itself for the first, a copy of it beside it for each after. **/
	function decoBox(deco:Deco, n:Int):DecoBox {
		while (deco.boxes.length <= n) {
			var copy = Owner.root(tree, _ -> new Div({tag: deco.tag, classes: deco.classes}, tree));
			Identity.of(tree, copy.node.id).anonymous = true;
			var parent = tree.ancestors(deco.node.id)[0];
			tree.addChild(parent, copy.node.id);
			deco.boxes.push(new DecoBox(copy.node));
		}
		return deco.boxes[n];
	}

	static function set(signal:Signal<Single>, v:Float):Bool {
		if (signal.get() == v)
			return false;
		signal.set(v);
		return true;
	}

	/** Puts each line's pieces and boxes in place, from `(dx, dy)`; true when anything moved. **/
	function place(lines:Array<Line>, dx:Float, dy:Float, width:Float, align:Align):Bool {
		var used = new Map<Run, Int>();
		var sig = new StringBuf();
		var y = 0.0;
		for (line in lines) {
			// Where the line starts, and what each space between its words gains when it is justified.
			var natural = 0.0, gaps = 0;
			// A space stretches unless it is inside a box around text, which keeps its words together.
			function stretches(k:Int):Bool
				return switch line.items[k].item {
					case Word(run, _, _, _, space) if (space > 0 && k < line.items.length - 1):
						run.deco == null || !line.items[k + 1].item.match(Word(_, _, _, _, _)) || switch line.items[k + 1].item {
							case Word(next, _, _, _, _): next != run;
							case _: true;
						}
					case _: false;
				}
			for (k => p in line.items) {
				natural = Math.max(natural, p.x + itemWidth(p.item));
				if (stretches(k))
					gaps++;
			}
			var free = Math.max(0, width - natural);
			var justify = align == Justify && !line.ends && gaps > 0;
			var shift = switch align {
				case Center: free / 2;
				case Right: free;
				case _: 0.0;
			}
			var extra = justify ? free / gaps : 0.0;
			// Each item's x, its line's shift and the spaces before it added.
			var xs = [];
			var gained = 0.0;
			for (k => p in line.items) {
				xs.push(p.x + shift + gained);
				if (justify && stretches(k))
					gained += extra;
			}
			var i = 0;
			while (i < line.items.length) {
				var p = line.items[i];
				var x = xs[i];
				switch p.item {
					case Word(run, start, _, _, _):
						// The run's words on this line, one piece; each word its own when the spaces between them are widened.
						var j = i, end = 0;
						while (j < line.items.length)
							switch line.items[j].item {
								case Word(r, _, e, _, _) if (r == run && (j == i || !justify || r.deco != null)):
									end = e;
									j++;
								case _:
									break;
							}
						var n = used.exists(run) ? used.get(run) : 0;
						used.set(run, n + 1);
						var deco = run.deco;
						// A box around the text: this line's, the element itself first, then copies of it.
						var box = deco == null ? null : decoBox(deco, n);
						if (n >= run.pieces.length) {
							var piece = Owner.root(tree, _ -> new Piece(tree));
							tree.addChild(box != null ? box.node.id : run.parent, piece.text.node.id);
							run.pieces.push(piece);
						}
						var piece = run.pieces[n];
						var text = run.text.substring(start, end);
						var left = dx + x, top = dy + y + line.above - run.above;
						if (box != null) {
							var pad = deco.padding;
							var inset = start == 0 ? pad.left : 0.0;
							var right = xs[j - 1] + itemWidth(line.items[j - 1].item);
							set(box.left, left);
							set(box.top, top - pad.top);
							set(box.width, dx + right - left);
							set(box.height, run.above + run.below + pad.top + pad.bottom);
							box.shown.set(Display.Flex);
							// Inside the box: after its padding where the text starts, at its top padding.
							left = inset;
							top = pad.top;
						}
						piece.content.set(text);
						set(piece.left, left);
						set(piece.top, top);
						piece.shown.set(Display.Flex);
						sig.add('$text@$left,$top;');
						i = j;
					case Box(atom):
						var left = dx + x, top = dy + y + line.above - atom.above;
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
		// Pieces, and boxes after the first, no line needs now are hidden, kept for later.
		for (run in runs) {
			var n = used.exists(run) ? used.get(run) : 0;
			for (k in n...run.pieces.length)
				run.pieces[k].shown.set(Display.None);
			if (run.deco != null)
				for (k in Std.int(Math.max(1, n))...run.deco.boxes.length)
					run.deco.boxes[k].shown.set(Display.None);
		}
		var heightChanged = set(spacerHeight, Math.ceil(y));
		var s = sig.toString();
		var moved = s != placed;
		placed = s;
		return moved || heightChanged;
	}
}
