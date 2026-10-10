package ashui.debug;

import ashui.layout.LayoutTree;

/** One element as a snapshot saw it. **/
typedef ElementShot = {
	/** Its node id, as text. **/
	id:String,
	parent:Null<String>,
	/** Its selector, `button.primary#save`. **/
	label:String,
	/** Its absolute box; `laidOut` false and zeros before layout. **/
	x:Float,
	y:Float,
	w:Float,
	h:Float,
	laidOut:Bool,
	/** Its computed CSS values with their `var()`s replaced, inherited ones and custom properties included. **/
	style:Map<String, String>,
	/** Its interaction states that hold: `hover`, `active`, `focus`, `focus-visible`, `disabled`. **/
	states:Array<String>
}

/** What changed for one element between two snapshots. **/
typedef ElementChange = {
	id:String,
	label:String,
	/** Its box before and after, when it moved or resized. **/
	?box:{from:String, to:String},
	/** Each property whose computed value changed: null where it had none. **/
	style:Array<{name:String, from:Null<String>, to:Null<String>}>,
	?states:{from:Array<String>, to:Array<String>}
}

/** What two snapshots of a tree differ by. **/
typedef TreeDiff = {
	added:Array<ElementShot>,
	removed:Array<ElementShot>,
	changed:Array<ElementChange>
}

/**
	The elements of a tree at one moment, in document order: each one's
	place in the tree, its box, its computed CSS and its interaction states.
	`diff` says what changed between two, as a debugger's tree view shows
	elements added, removed, moved and restyled.

	```haxe
	var before = TreeSnapshot.take(tree);
	// … input, a frame …
	trace(TreeSnapshot.lines(TreeSnapshot.diff(before, TreeSnapshot.take(tree))));
	```
**/
class TreeSnapshot {
	/** The animation clock when it was taken. **/
	public final clock:Float;

	public final elements:Array<ElementShot>;

	function new(clock:Float, elements:Array<ElementShot>) {
		this.clock = clock;
		this.elements = elements;
	}

	/** The elements under `root`, the tree's root by default, `root` included. **/
	public static function take(tree:LayoutTree, ?root:haxe.Int64):TreeSnapshot {
		var out = [];
		var start = root != null ? root : tree.root == null ? null : tree.root.id;
		if (start != null)
			visit(tree, start, null, out);
		return new TreeSnapshot(ashui.animation.AnimationScheduler.main.clock, out);
	}

	static function visit(tree:LayoutTree, node:haxe.Int64, parent:Null<String>, out:Array<ElementShot>):Void {
		var id = haxe.Int64.toStr(node);
		var b = tree.getBounds(new ashui.layout.Node(node));
		var identity = ashui.css.Identity.of(tree, node);
		var style = new Map<String, String>();
		if (identity != null) {
			var applied = @:privateAccess ashui.css.Css.applied.get(identity);
			if (applied != null)
				for (k => v in applied.values)
					style.set(k, v.indexOf("var(") >= 0 ? ashui.css.Css.resolve(identity, v) : v);
		}
		out.push({
			id: id,
			parent: parent,
			label: MotionTrace.describe(tree, node),
			x: b == null ? 0 : b.x,
			y: b == null ? 0 : b.y,
			w: b == null ? 0 : b.width,
			h: b == null ? 0 : b.height,
			laidOut: b != null,
			style: style,
			states: states(tree, node)
		});
		for (child in tree.children(node))
			visit(tree, child, id, out);
	}

	/** `node`'s interaction states that hold: `hover`, `active`, `focus`, `focus-visible`, `disabled`. **/
	public static function states(tree:LayoutTree, node:haxe.Int64):Array<String> {
		var i = ashui.input.Interaction.byId(tree, node);
		if (i == null)
			return [];
		var out = [];
		if (i.hovered.get())
			out.push("hover");
		if (i.pressed.get())
			out.push("active");
		if (i.focused.get())
			out.push("focus");
		if (i.focusVisible.get())
			out.push("focus-visible");
		if (i.disabled.get())
			out.push("disabled");
		return out;
	}

	/** What changed from `a` to `b`: elements added and removed by id, and those in both whose box, computed CSS or states differ. **/
	public static function diff(a:TreeSnapshot, b:TreeSnapshot):TreeDiff {
		var before = [for (e in a.elements) e.id => e];
		var after = [for (e in b.elements) e.id => e];
		var added = [for (e in b.elements) if (!before.exists(e.id)) e];
		var removed = [for (e in a.elements) if (!after.exists(e.id)) e];
		var changed:Array<ElementChange> = [];
		for (e in b.elements) {
			var was = before.get(e.id);
			if (was == null)
				continue;
			var c:ElementChange = {id: e.id, label: e.label, style: []};
			var from = box(was), to = box(e);
			if (from != to)
				c.box = {from: from, to: to};
			var names = [for (k in was.style.keys()) k];
			for (k in e.style.keys())
				if (!was.style.exists(k))
					names.push(k);
			names.sort(Reflect.compare);
			for (name in names) {
				var x = was.style.get(name), y = e.style.get(name);
				if (x != y)
					c.style.push({name: name, from: x, to: y});
			}
			if (was.states.join(" ") != e.states.join(" "))
				c.states = {from: was.states, to: e.states};
			if (c.box != null || c.style.length > 0 || c.states != null)
				changed.push(c);
		}
		return {added: added, removed: removed, changed: changed};
	}

	static function box(e:ElementShot):String
		return e.laidOut ? '${r(e.x)},${r(e.y)} ${r(e.w)}x${r(e.h)}' : "not laid out";

	static function r(v:Float):String
		return Std.string(Math.round(v * 10) / 10);

	/**
		A diff as lines: `+` an element added, `-` removed, `~` changed, with
		what changed indented under it. Given the `tree` the second snapshot
		was taken of, each restyled value also names the rule it came from.
	**/
	public static function lines(d:TreeDiff, ?tree:LayoutTree):String {
		var out = [];
		for (e in d.added)
			out.push('+ ${e.label} #${e.id}');
		for (e in d.removed)
			out.push('- ${e.label} #${e.id}');
		for (c in d.changed) {
			out.push('~ ${c.label} #${c.id}');
			if (c.box != null)
				out.push('    box: ${c.box.from} -> ${c.box.to}');
			if (c.states != null)
				out.push('    states: [${c.states.from.join(" ")}] -> [${c.states.to.join(" ")}]');
			var origins = tree == null || c.style.length == 0 ? null : winners(tree, c.id);
			for (s in c.style) {
				var from = origins == null ? null : origins.get(s.name);
				out.push('    ${s.name}: ${s.from == null ? "(none)" : s.from} -> ${s.to == null ? "(none)" : s.to}' + (from == null ? "" : '  [$from]'));
			}
		}
		return out.join("\n");
	}

	/** Where each winning declaration of element `id` came from, by property. **/
	static function winners(tree:LayoutTree, id:String):Null<Map<String, String>> {
		var identity = ashui.css.Identity.of(tree, haxe.Int64.parseString(id));
		if (identity == null)
			return null;
		return [for (o in ashui.css.Css.explain(identity)) if (o.wins) o.name => ashui.css.Css.where(o)];
	}

	/** The snapshot as JSON, for a debugger or a script to read. **/
	public function json():String
		return haxe.Json.stringify({
			clock: clock,
			elements: [
				for (e in elements)
					{
						id: e.id,
						parent: e.parent,
						label: e.label,
						box: e.laidOut ? [e.x, e.y, e.w, e.h] : null,
						style: [for (k => v in e.style) {name: k, value: v}],
						states: e.states
					}
			]
		});
}
