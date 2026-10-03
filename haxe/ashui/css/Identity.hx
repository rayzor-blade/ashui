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

	/** Element types, most specific last: a component's tag after its root's `div`. **/
	public final types:Array<String> = [];

	public var id(default, null):Null<String> = null;

	static final NONE:Array<String> = [];

	/** Constant classes. **/
	var fixed:Array<String> = NONE;

	/** Classes that follow a signal or computed; only an element given such has one. **/
	var classSignal:Null<Signal<Array<String>>> = null;

	function new() {}

	/** The identity of the node `id` of `tree`, null if it has none. **/
	public static function of(tree:LayoutTree, node:haxe.Int64):Null<Identity> {
		var nodes = trees.get(tree);
		return nodes == null ? null : nodes.get(key(node));
	}

	/** Registers the node `node` of `tree` as being of `type`, adding the type if it has an identity already. **/
	public static function register(tree:LayoutTree, node:haxe.Int64, type:String):Identity {
		var nodes = trees.get(tree);
		if (nodes == null)
			trees.set(tree, nodes = new Map());
		var k = key(node);
		var identity = nodes.get(k);
		if (identity == null)
			nodes.set(k, identity = new Identity());
		if (identity.types.indexOf(type) < 0)
			identity.types.push(type);
		return identity;
	}

	/** Drops the node's identity, when the node is removed. **/
	public static function forget(tree:LayoutTree, node:haxe.Int64):Void {
		var nodes = trees.get(tree);
		if (nodes != null)
			nodes.remove(key(node));
	}

	/** Drops the identities of `node` and everything below it, when they are removed together. **/
	public static function forgetSubtree(tree:LayoutTree, node:haxe.Int64):Void {
		var nodes = trees.get(tree);
		if (nodes == null)
			return;
		var stack = [node];
		while (stack.length > 0) {
			var at = stack.pop();
			nodes.remove(key(at));
			for (child in tree.children(at))
				stack.push(child);
		}
	}

	/** Sets the id, `#id` in CSS. **/
	public function setId(value:Null<String>):Identity {
		id = value;
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
		new ashui.reactive.Watch(read, list -> target.set(list));
	}

	/** The classes now; read inside a computed, it follows them. **/
	public function classes():Array<String>
		return classSignal == null ? fixed : classSignal.get();

	/** Whether it has class `name` now. **/
	public inline function hasClass(name:String):Bool
		return classes().indexOf(name) >= 0;

	static inline function key(id:haxe.Int64):String
		return haxe.Int64.toStr(id);
}
