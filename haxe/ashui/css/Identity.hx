package ashui.css;

import ashui.layout.IntoReactive;
import ashui.layout.LayoutTree;
import ashui.reactive.Signal;

/**
	What CSS selectors know an element by: its types (`div`, `text`,
	`img`, `svg`, and a component's tag, `counter-view`, on the node its
	render made), its id and its classes. The classes are a signal, so a
	class added or removed later is matched again.

	Every element registers one when it is made, and leaves when it is
	removed; `of` finds a node's.
**/
class Identity {
	static final trees = new haxe.ds.ObjectMap<LayoutTree, Map<String, Identity>>();

	/** The node it is the identity of. **/
	public final node:ashui.layout.Node;

	/** Element types, most specific last: a component's tag after its root's `div`. **/
	public final types:Array<String> = [];

	public var id(default, null):Null<String> = null;

	/**
		Not counted among its siblings: a node a layout adds, as text flow's
		pieces are, is skipped by `:first-child`, `:nth-child`, `+` and `~`,
		so they see the elements the author wrote. Its own type and classes
		still match.
	**/
	public var anonymous(default, set) = false;

	function set_anonymous(v:Bool):Bool {
		if (v != anonymous) {
			anonymous = v;
			for (hook in hooks)
				hook(this);
		}
		return v;
	}

	/** The tree its node is in. **/
	public var tree(default, null):LayoutTree;

	static final NONE:Array<String> = [];

	/** Attributes CSS's `[name=value]` tests, as HTML elements have: `type`, `name`, `value`. **/
	var attributes:Null<Map<String, String>> = null;

	/** Declarations of its own, as HTML's `style` attribute holds: over every rule that matches it but an `!important` one, and inherited as the cascade's values are. **/
	var declared:Null<Map<String, String>> = null;

	/** Declares `name: value` on it inline, or takes the declaration away with null. **/
	public function setInline(name:String, value:Null<String>):Identity {
		if (value == null) {
			if (declared == null || !declared.remove(name))
				return this;
		} else {
			if (declared == null)
				declared = new Map();
			if (declared.get(name) == value)
				return this;
			declared.set(name, value);
			// The cascade watches elements once a sheet loads; one declared on its own is watched from now.
			Css.hook();
		}
		for (hook in hooks)
			hook(this);
		return this;
	}

	/** Its inline declarations, or null when it has none. **/
	public function inlineDeclarations():Null<Map<String, String>>
		return declared;

	/** `node`'s identity, made as a `div`'s when it has none, with `name: value` declared on it inline: what Tw's text classes write. **/
	public static function declare(node:ashui.layout.Node, name:String, value:String):Void {
		var tree = node.tree;
		var identity = of(tree, node.id);
		if (identity == null)
			identity = register(tree, node, "div");
		identity.setInline(name, value);
	}

	/** Sets attribute `name` to `value`, or removes it with null. **/
	public function setAttribute(name:String, value:Null<String>):Identity {
		if (value == null) {
			if (attributes == null || !attributes.remove(name))
				return this;
		} else {
			if (attributes == null)
				attributes = new Map();
			if (attributes.get(name) == value)
				return this;
			attributes.set(name, value);
		}
		for (hook in hooks)
			hook(this);
		return this;
	}

	/** Sets attribute `name` from a constant, or follows a signal or computed of its value, null taking it away. **/
	public function bindAttribute(name:String, value:IntoReactive<Null<String>>):Identity {
		switch (value : ashui.layout.IntoReactive.ReactiveType<Null<String>>) {
			case Const(v):
				setAttribute(name, v);
			case Bound(s):
				setAttribute(name, s.get());
				new ashui.reactive.Watch(() -> s.get(), v -> setAttribute(name, v));
			case Derived(c):
				setAttribute(name, c.get());
				new ashui.reactive.Watch(() -> c.get(), v -> setAttribute(name, v));
		}
		return this;
	}

	/** Attribute `name`'s value, null when it has none. **/
	public function attribute(name:String):Null<String>
		return attributes == null ? null : attributes.get(name);

	/** Constant classes. **/
	var fixed:Array<String> = NONE;

	/** Classes that follow a signal or computed; only an element given such has one. **/
	var classSignal:Null<Signal<Array<String>>> = null;

	function new(node:ashui.layout.Node)
		this.node = node;

	/** The identity of the node `id` of `tree`, null if it has none. **/
	public static function of(tree:LayoutTree, node:haxe.Int64):Null<Identity> {
		var nodes = trees.get(tree);
		return nodes == null ? null : nodes.get(key(node));
	}

	/** Called with each identity made, and with one whose classes change. **/
	public static final hooks:Array<Identity->Void> = [];

	/** Called with each identity forgotten, its node removed. **/
	public static final forgetHooks:Array<Identity->Void> = [];

	/** Registers `node` of `tree` as being of `type`, adding the type if it has an identity already. **/
	public static function register(tree:LayoutTree, node:ashui.layout.Node, type:String):Identity {
		var nodes = trees.get(tree);
		if (nodes == null)
			trees.set(tree, nodes = new Map());
		var k = key(node.id);
		var identity = nodes.get(k);
		if (identity == null) {
			nodes.set(k, identity = new Identity(node));
			identity.tree = tree;
		}
		if (identity.types.indexOf(type) < 0)
			identity.types.push(type);
		for (hook in hooks)
			hook(identity);
		return identity;
	}

	/** Drops the node's identity, when the node is removed. **/
	public static function forget(tree:LayoutTree, node:haxe.Int64):Void {
		var nodes = trees.get(tree);
		if (nodes == null)
			return;
		var identity = nodes.get(key(node));
		if (identity != null) {
			nodes.remove(key(node));
			for (hook in forgetHooks)
				hook(identity);
		}
	}

	/** Drops the identities of `node` and everything below it, when they are removed together. **/
	public static function forgetSubtree(tree:LayoutTree, node:haxe.Int64):Void {
		var nodes = trees.get(tree);
		if (nodes == null)
			return;
		var stack = [node];
		while (stack.length > 0) {
			var at = stack.pop();
			var identity = nodes.get(key(at));
			if (identity != null) {
				nodes.remove(key(at));
				for (hook in forgetHooks)
					hook(identity);
			}
			for (child in tree.children(at))
				stack.push(child);
		}
	}

	/** Sets the id, `#id` in CSS. **/
	public function setId(value:Null<String>):Identity {
		id = value;
		for (hook in hooks)
			hook(this);
		return this;
	}

	/** Sets the classes, a constant or something they follow. **/
	public function setClasses(value:IntoReactive<Array<String>>):Identity {
		switch (value : ReactiveType<Array<String>>) {
			case Const(list):
				if (classSignal != null)
					classSignal.set(list);
				else
					fixed = list;
				for (hook in hooks)
					hook(this);
			case Bound(source):
				follow(() -> source.get());
			case Derived(source):
				follow(() -> source.get());
		}
		return this;
	}

	function follow(read:Void->Array<String>):Void {
		if (classSignal == null)
			classSignal = Signal.make(fixed);
		var target = classSignal;
		new ashui.reactive.Watch(read, list -> {
			target.set(list);
			for (hook in hooks)
				hook(this);
		});
	}

	/** Classes added beside its own (see `addClasses`), as an author's on a component. **/
	var added:Array<String> = NONE;

	/** Adds `list` to its classes, beside those it sets itself, as `class=` on a component adds the author's to the component's own. **/
	public function addClasses(list:Array<String>):Identity {
		added = added.concat([for (c in list) if (added.indexOf(c) < 0) c]);
		for (hook in hooks)
			hook(this);
		return this;
	}

	/** The classes now, its own and those added; read inside a computed, it follows them. **/
	public function classes():Array<String> {
		var own = classSignal == null ? fixed : classSignal.get();
		return added.length == 0 ? own : own.concat(added);
	}

	/** Whether it has class `name` now. **/
	public inline function hasClass(name:String):Bool
		return classes().indexOf(name) >= 0;

	static inline function key(id:haxe.Int64):String
		return haxe.Int64.toStr(id);
}
