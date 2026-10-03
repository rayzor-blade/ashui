package ashui.css;

import ashui.css.CssValue;
import ashui.css.Selector;
import ashui.css.Stylesheet;
import ashui.layout.LayoutTree;

private typedef Matched = {
	final declaration:Declaration;
	final important:Bool;
	final specificity:Int;
	final sheet:Int;
	final order:Int;
	final index:Int;
}

/** What the cascade left on an element last time: its winning values and the fields they wrote. **/
private typedef Applied = {
	/** Each property's winning value, for inheritance and to skip an unchanged restyle. **/
	final values:Map<String, String>;

	final signature:String;
	final fields:Array<Int>;
}

/**
	The stylesheets in force and how they reach elements.

	`Css.add(sheet)` puts a parsed `Stylesheet` in force (`Css.load` parses
	and adds CSS text). Every element is then matched against its rules:
	when it is made, when a sheet is added or removed, when its classes or
	id change, and when the children of an element above or beside it
	change, at the next `LayoutTree.flush`. Nothing is re-matched
	otherwise, so a frame that changes no structure or class costs nothing.

	The cascade is CSS's, property by property: `!important` over normal,
	then specificity, then order (a later sheet's rule after an earlier
	sheet's, a later rule after an earlier one). As in Tailwind's layers, a
	stylesheet sits under what an element sets itself: its Tw classes, its
	`style=` and its attributes win over any rule. When no rule sets a
	property any more, it goes back to what a new element has.

	Text inherits `font-size`, `font-weight`, `font-style`, `font-family`,
	`line-height`, `letter-spacing` and `text-align` from the elements
	around it, as CSS's inherited properties do; `color` is inherited by
	drawing. `var(--name, fallback)` reads the custom properties of `:root`
	rules and of the element and its ancestors.

	State pseudo-classes, `:hover` and the like, match nothing yet.
**/
class Css {
	/** The sheets in force, in order. **/
	static final sheets:Array<Stylesheet> = [];

	/** Problems found applying declarations, each once: an unknown property, a value that does not read. **/
	public static final problems:Array<String> = [];

	/** What `vw` and `vh` are a hundredth of; set it from the window's size. **/
	public static var viewportWidth = 0.0;

	public static var viewportHeight = 0.0;

	/** What `rem` is, and the font size of text with none of its own. **/
	public static var rootFontSize = 16.0;

	static final pending = new haxe.ds.ObjectMap<LayoutTree, Map<String, Identity>>();
	static final applied = new haxe.ds.ObjectMap<Identity, Applied>();
	static final reported = new Map<String, Bool>();
	static var hooked = false;

	/** Rules by their subject's id, class, type, or none of those, for each sheet. **/
	static var index:Array<{ids:Map<String, Array<Entry>>, classes:Map<String, Array<Entry>>, types:Map<String, Array<Entry>>, rest:Array<Entry>}> = [];

	static var usesHas = false;

	/** Parses `source` and puts it in force; its problems are the returned sheet's `diagnostics`. **/
	public static function load(source:String, ?file:String):Stylesheet {
		var sheet = Stylesheet.parse(source, file);
		add(sheet);
		return sheet;
	}

	/** Puts `sheet` in force, after those already in force; a property it names that this does not apply is a warning in its `diagnostics`. **/
	public static function add(sheet:Stylesheet):Void {
		unknown(sheet);
		sheets.push(sheet);
		changed();
	}

	static function unknown(sheet:Stylesheet):Void {
		for (rule in sheet.rules)
			for (d in rule.declarations)
				if (!StringTools.startsWith(d.name, "--") && !Properties.known(d.name))
					sheet.diagnostics.push({
						severity: Warning,
						message: '${d.name} is not a property this supports',
						line: d.line,
						column: d.column
					});
	}

	/** Takes `sheet` out of force; what only it set goes back. **/
	public static function remove(sheet:Stylesheet):Void {
		if (sheets.remove(sheet))
			changed();
	}

	/** Puts `next` in `previous`'s place, as a reloaded file does, keeping its order. **/
	public static function replace(previous:Stylesheet, next:Stylesheet):Void {
		unknown(next);
		var i = sheets.indexOf(previous);
		if (i < 0)
			sheets.push(next);
		else
			sheets[i] = next;
		changed();
	}

	/** Takes every sheet out of force. **/
	public static function clear():Void {
		if (sheets.length == 0)
			return;
		sheets.resize(0);
		changed();
	}

	static function changed():Void {
		hook();
		index = [for (sheet in sheets) indexOf(sheet)];
		usesHas = Lambda.exists(sheets, s -> Lambda.exists(s.rules, r -> Lambda.exists(r.selectors, hasHas)));
		// Every element, to be matched again.
		for (tree => nodes in @:privateAccess Identity.trees)
			for (identity in nodes)
				mark(identity);
	}

	static function hook():Void {
		if (hooked)
			return;
		hooked = true;
		Identity.hooks.push(identity -> if (sheets.length > 0 || applied.exists(identity)) mark(identity));
		LayoutTree.childrenHooks.push((tree, parent) -> if (sheets.length > 0) markSubtree(tree, parent));
		LayoutTree.flushHooks.push(flush);
	}

	// --- What to match again ---

	static function mark(identity:Identity):Void {
		var tree = identity.tree;
		var nodes = pending.get(tree);
		if (nodes == null)
			pending.set(tree, nodes = new Map());
		nodes.set(haxe.Int64.toStr(identity.node.id), identity);
	}

	/** `parent` and everything under it, and with `:has()` in force, its ancestors. **/
	static function markSubtree(tree:LayoutTree, parent:haxe.Int64):Void {
		var stack = [parent];
		while (stack.length > 0) {
			var at = stack.pop();
			var identity = Identity.of(tree, at);
			if (identity != null)
				mark(identity);
			for (child in tree.children(at))
				stack.push(child);
		}
		if (usesHas)
			for (up in tree.ancestors(parent)) {
				var identity = Identity.of(tree, up);
				if (identity != null)
					mark(identity);
			}
	}

	// --- Applying ---

	static function flush(tree:LayoutTree):Void {
		var nodes = pending.get(tree);
		if (nodes == null)
			return;
		pending.remove(tree);
		var walk = new TreeWalk(tree);
		// Parents first, so a child inherits what its parent has now.
		var list = [for (identity in nodes) identity];
		var depth = new Map<String, Int>();
		for (identity in list)
			depth.set(haxe.Int64.toStr(identity.node.id), walk.ancestors(identity.node.id).length);
		list.sort((a, b) -> depth.get(haxe.Int64.toStr(a.node.id)) - depth.get(haxe.Int64.toStr(b.node.id)));
		for (identity in list)
			if (Identity.of(tree, identity.node.id) == identity)
				restyle(identity, walk);
	}

	static function restyle(identity:Identity, walk:TreeWalk):Void {
		var node = identity.node.id;
		// The declarations of every rule that matches, in cascade order.
		var matched:Array<Matched> = [];
		for (s => entries in index)
			for (entry in candidates(entries, identity)) {
				if (!walk.matches(entry.selector, node))
					continue;
				for (i => d in entry.rule.declarations)
					matched.push({
						declaration: d,
						important: d.important,
						specificity: entry.selector.specificity(),
						sheet: s,
						order: entry.rule.order,
						index: i
					});
			}
		matched.sort((a, b) -> a.important != b.important ? (a.important ? 1 : -1) : a.specificity != b.specificity ? a.specificity
			- b.specificity : a.sheet != b.sheet ? a.sheet - b.sheet : a.order != b.order ? a.order - b.order : a.index - b.index);
		// The same declaration may come from two selectors of one rule; the last stands.
		var own = new Map<String, String>();
		var from = new Map<String, Declaration>();
		for (m in matched) {
			own.set(m.declaration.name, m.declaration.value);
			from.set(m.declaration.name, m.declaration);
		}

		// What it inherits from its parent, under its own.
		var parent = walk.parent(node);
		var inherited:Null<Applied> = null;
		if (parent != null) {
			var p = Identity.of(identity.tree, parent);
			if (p != null)
				inherited = applied.get(p);
		}
		var values = new Map<String, String>();
		if (inherited != null)
			for (name => v in inherited.values)
				if (INHERITED.indexOf(name) >= 0 || StringTools.startsWith(name, "--"))
					values.set(name, v);
		for (name => v in own)
			values.set(name, v);

		// Variables first, so declarations that read them see them.
		var resolved = new Map<String, String>();
		var text = identity.types.indexOf("text") >= 0;
		for (name => v in values) {
			if (StringTools.startsWith(name, "--"))
				continue;
			// Inherited font properties reach text alone; other elements take only their own.
			if (!own.exists(name) && !text)
				continue;
			resolved.set(name, substitute(v, values));
		}
		var signature = [for (name => v in resolved) '$name:$v'];
		signature.sort(Reflect.compare);
		var sig = signature.join(";");
		var last = applied.get(identity);
		if (last != null && last.signature == sig) {
			applied.set(identity, {values: values, signature: sig, fields: last.fields});
			return;
		}

		var fontSize = rootFontSize;
		if (inherited != null && inherited.values.exists("font-size"))
			fontSize = pixelsOr(inherited.values.get("font-size"), rootFontSize);
		var ctx:Properties.ApplyContext = {
			viewportWidth: viewportWidth,
			viewportHeight: viewportHeight,
			fontSize: fontSize,
			rootFontSize: rootFontSize,
			currentColor: values.exists("color") ? (try CssValue.color(substitute(values.get("color"), values)) catch (_:String) CurrentColor) : CurrentColor
		};
		var fields:Array<Int> = [];
		// font-size first: em in the rest is the element's own font size.
		var names = [for (name in resolved.keys()) name];
		names.sort((a, b) -> a == "font-size" ? -1 : b == "font-size" ? 1 : Reflect.compare(a, b));
		for (name in names) {
			var v = resolved.get(name);
			if (!Properties.known(name)) {
				report(from.get(name), '$name is not a property this supports');
				continue;
			}
			try {
				for (f in Properties.apply(identity.node, name, v, ctx))
					fields.push(f);
			} catch (e:String) {
				report(from.get(name), '$name: $e');
			}
			if (name == "font-size")
				ctx = {
					viewportWidth: ctx.viewportWidth,
					viewportHeight: ctx.viewportHeight,
					fontSize: pixelsOr(v, ctx.fontSize),
					rootFontSize: ctx.rootFontSize,
					currentColor: ctx.currentColor
				};
		}
		if (last != null)
			for (f in last.fields)
				if (fields.indexOf(f) < 0)
					@:privateAccess identity.node.unstyle(f);
		applied.set(identity, {values: values, signature: sig, fields: fields});

		// Inherited values changed: the children inherit again.
		if (last == null || inheritedSignature(last.values) != inheritedSignature(values))
			for (child in walk.children(node)) {
				var c = Identity.of(identity.tree, child);
				if (c != null)
					restyle(c, walk);
			}
	}

	static final INHERITED = ["color", "font-size", "font-weight", "font-style", "font-family", "line-height", "letter-spacing", "text-align"];

	static function inheritedSignature(values:Map<String, String>):String {
		var out = [for (name => v in values) if (INHERITED.indexOf(name) >= 0 || StringTools.startsWith(name, "--")) '$name:$v'];
		out.sort(Reflect.compare);
		return out.join(";");
	}

	/** `var(--name, fallback)` replaced by the element's custom property, then `:root`'s, then the fallback. **/
	static function substitute(value:String, values:Map<String, String>):String {
		var pass = 0;
		while (value.indexOf("var(") >= 0 && pass++ < 10) {
			var at = value.indexOf("var(");
			var depth = 0, end = at + 4;
			while (end < value.length) {
				var c = value.charAt(end);
				if (c == "(")
					depth++;
				else if (c == ")") {
					if (depth == 0)
						break;
					depth--;
				}
				end++;
			}
			var args = value.substring(at + 4, end);
			var comma = args.indexOf(",");
			var name = StringTools.trim(comma < 0 ? args : args.substr(0, comma));
			var fallback = comma < 0 ? null : StringTools.trim(args.substr(comma + 1));
			var found = values.get(name);
			if (found == null)
				for (sheet in sheets) {
					var v = sheet.variables.get(name.substr(2));
					if (v != null)
						found = v;
				}
			if (found == null)
				found = fallback == null ? "" : fallback;
			value = value.substr(0, at) + found + value.substr(end + 1);
		}
		return value;
	}

	static function pixelsOr(v:String, fallback:Float):Float {
		return try CssValue.resolve(CssValue.length(v), {
			percentOf: fallback,
			fontSize: fallback,
			rootFontSize: rootFontSize,
			viewportWidth: viewportWidth,
			viewportHeight: viewportHeight
		}) catch (_:String) fallback;
	}

	static function report(d:Null<Declaration>, message:String):Void {
		var where = d == null ? "" : '${d.line}:${d.column}: ';
		var line = where + message;
		if (reported.exists(line))
			return;
		reported.set(line, true);
		problems.push(line);
	}

	// --- Rule index ---

	static function indexOf(sheet:Stylesheet) {
		var ids = new Map<String, Array<Entry>>(), classes = new Map<String, Array<Entry>>(), types = new Map<String, Array<Entry>>();
		var rest:Array<Entry> = [];
		function add(map:Map<String, Array<Entry>>, key:String, e:Entry) {
			var list = map.get(key);
			if (list == null)
				map.set(key, list = []);
			list.push(e);
		}
		for (rule in sheet.rules)
			for (selector in rule.selectors) {
				var e:Entry = {rule: rule, selector: selector};
				var subject = selector.subject;
				if (subject.id != null)
					add(ids, subject.id, e);
				else if (subject.classes.length > 0)
					add(classes, subject.classes[0], e);
				else if (subject.type != null)
					add(types, subject.type, e);
				else
					rest.push(e);
			}
		return {ids: ids, classes: classes, types: types, rest: rest};
	}

	static function candidates(index:{ids:Map<String, Array<Entry>>, classes:Map<String, Array<Entry>>, types:Map<String, Array<Entry>>, rest:Array<Entry>},
			identity:Identity):Array<Entry> {
		var out = index.rest.copy();
		if (identity.id != null && index.ids.exists(identity.id))
			out = out.concat(index.ids.get(identity.id));
		for (c in identity.classes())
			if (index.classes.exists(c))
				out = out.concat(index.classes.get(c));
		for (t in identity.types)
			if (index.types.exists(t))
				out = out.concat(index.types.get(t));
		return out;
	}

	static function hasHas(s:Selector):Bool
		return Lambda.exists(s.compounds, c -> Lambda.exists(c.pseudos, p -> switch p {
			case Has(_): true;
			case Not(inner) | Is(inner) | Where(inner): Lambda.exists(inner, hasHas);
			case _: false;
		}));
}

private typedef Entry = {
	final rule:StyleRule;
	final selector:Selector;
}

/** Selector matching over a tree, caching what it asks the tree. **/
private class TreeWalk {
	final tree:LayoutTree;
	final up = new Map<String, Array<haxe.Int64>>();
	final down = new Map<String, Array<haxe.Int64>>();

	public function new(tree:LayoutTree)
		this.tree = tree;

	public function ancestors(node:haxe.Int64):Array<haxe.Int64> {
		var k = haxe.Int64.toStr(node);
		var a = up.get(k);
		if (a == null)
			up.set(k, a = tree.ancestors(node));
		return a;
	}

	public function children(node:haxe.Int64):Array<haxe.Int64> {
		var k = haxe.Int64.toStr(node);
		var c = down.get(k);
		if (c == null)
			down.set(k, c = tree.children(node));
		return c;
	}

	public function parent(node:haxe.Int64):Null<haxe.Int64> {
		var a = ancestors(node);
		return a.length == 0 ? null : a[0];
	}

	function siblings(node:haxe.Int64):Array<haxe.Int64> {
		var p = parent(node);
		return p == null ? [node] : children(p);
	}

	/** Whether `selector` matches `node` as its subject. **/
	public function matches(selector:Selector, node:haxe.Int64):Bool
		return at(selector, selector.compounds.length - 1, node, null);

	/**
		Whether compound `i` of `selector` matches `node`, and the compounds
		before it match where its combinators say, right to left; in a
		`:has()` argument, the first compound must also stand to `anchor` as
		its leading combinator says.
	**/
	function at(selector:Selector, i:Int, node:haxe.Int64, anchor:Null<haxe.Int64>):Bool {
		if (!compound(selector.compounds[i], node))
			return false;
		if (i == 0)
			return anchor == null || related(anchor, node, selector.leading == null ? Descendant : selector.leading);
		switch selector.combinators[i - 1] {
			case Child:
				var p = parent(node);
				return p != null && at(selector, i - 1, p, anchor);
			case Descendant:
				for (a in ancestors(node))
					if (at(selector, i - 1, a, anchor))
						return true;
				return false;
			case NextSibling:
				var s = siblings(node);
				var k = s.indexOf(node);
				return k > 0 && at(selector, i - 1, s[k - 1], anchor);
			case LaterSibling:
				var s = siblings(node);
				var k = s.indexOf(node);
				for (j in 0...Std.int(Math.max(0, k)))
					if (at(selector, i - 1, s[j], anchor))
						return true;
				return false;
		}
	}

	/** Whether `node` stands to `anchor` as `how` says: inside it, its child, the next sibling or a later one. **/
	function related(anchor:haxe.Int64, node:haxe.Int64, how:Combinator):Bool {
		return switch how {
			case Descendant: ancestors(node).indexOf(anchor) >= 0;
			case Child: parent(node) == anchor;
			case NextSibling:
				var s = siblings(node);
				var k = s.indexOf(node);
				k > 0 && s[k - 1] == anchor;
			case LaterSibling:
				var s = siblings(node);
				var k = s.indexOf(node);
				var j = s.indexOf(anchor);
				j >= 0 && j < k;
		}
	}

	function compound(c:Compound, node:haxe.Int64):Bool {
		var identity = Identity.of(tree, node);
		if (identity == null)
			return false;
		if (c.type != null && identity.types.indexOf(c.type) < 0)
			return false;
		if (c.id != null && identity.id != c.id)
			return false;
		for (name in c.classes)
			if (!identity.hasClass(name))
				return false;
		if (c.pseudoElement != null)
			return false;
		for (p in c.pseudos)
			if (!pseudo(p, node, identity))
				return false;
		return true;
	}

	function pseudo(p:Pseudo, node:haxe.Int64, identity:Identity):Bool {
		inline function index(of:Array<haxe.Int64>):Int
			return of.indexOf(node) + 1;
		inline function ofType(list:Array<haxe.Int64>):Array<haxe.Int64> {
			var type = identity.types[0];
			return list.filter(n -> {
				var other = Identity.of(tree, n);
				other != null && other.types[0] == type;
			});
		}
		return switch p {
			case State(_): false;
			case Root:
				tree.root != null ? tree.root.id == node : parent(node) == null;
			case Empty: children(node).length == 0;
			case FirstChild: index(siblings(node)) == 1;
			case LastChild:
				var s = siblings(node);
				index(s) == s.length;
			case OnlyChild: siblings(node).length == 1;
			case NthChild(n): nth(n, index(siblings(node)));
			case NthLastChild(n):
				var s = siblings(node);
				nth(n, s.length - index(s) + 1);
			case FirstOfType: index(ofType(siblings(node))) == 1;
			case LastOfType:
				var s = ofType(siblings(node));
				index(s) == s.length;
			case OnlyOfType: ofType(siblings(node)).length == 1;
			case NthOfType(n): nth(n, index(ofType(siblings(node))));
			case NthLastOfType(n):
				var s = ofType(siblings(node));
				nth(n, s.length - index(s) + 1);
			case Not(list): !Lambda.exists(list, s -> matches(s, node));
			case Is(list) | Where(list): Lambda.exists(list, s -> matches(s, node));
			case Has(list): Lambda.exists(list, s -> has(s, node));
		}
	}

	/** Whether an element related to `anchor` as `selector`'s leading combinator says matches it. **/
	function has(selector:Selector, anchor:haxe.Int64):Bool {
		var last = selector.compounds.length - 1;
		var how = selector.leading == null ? Descendant : selector.leading;
		var candidates:Array<haxe.Int64> = switch how {
			case NextSibling | LaterSibling:
				var s = siblings(anchor);
				var k = s.indexOf(anchor);
				var after = s.slice(k + 1);
				var out = [];
				for (n in after)
					for (d in subtree(n))
						out.push(d);
				out;
			case _:
				var out = subtree(anchor);
				out.shift();
				out;
		}
		for (n in candidates)
			if (at(selector, last, n, anchor))
				return true;
		return false;
	}

	function subtree(node:haxe.Int64):Array<haxe.Int64> {
		var out = [];
		var stack = [node];
		while (stack.length > 0) {
			var n = stack.pop();
			out.push(n);
			var c = children(n);
			var i = c.length;
			while (i-- > 0)
				stack.push(c[i]);
		}
		return out;
	}

	/** Whether position `i`, from 1, is `a·k + b` for some k ≥ 0. **/
	static function nth(n:Nth, i:Int):Bool {
		if (i < 1)
			return false;
		if (n.a == 0)
			return i == n.b;
		var k = (i - n.b) / n.a;
		return k >= 0 && k == Math.ffloor(k);
	}
}
