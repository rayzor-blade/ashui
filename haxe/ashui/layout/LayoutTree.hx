package ashui.layout;

import ashui.core.Utf8;
import ashui.core.externs.LayoutTreeNative;
import ashui.reactive.Guard;
import ashui.reactive.Watch;
import ashui.types.Style.GenericFont;

/**
	A layout tree: the nodes an element hierarchy is laid out and drawn from.
	A program can have any number; they are views onto one tree Blinc keeps
	for the process, so a node, its bindings and its queued writes belong to
	exactly one of them. Its nodes are removed when this object is collected,
	or at once with `dispose`.
**/
class LayoutTree {
	public var ptr(default, null):hl.Abstract<"blinc_tree">;

	/** The node `computeLayout` last laid out from, which input is hit-tested under. **/
	public var root(default, null):Null<Node>;

	public function new() {
		this.ptr = LayoutTreeNative.blinc_tree_new();
	}

	/**
		Frees the tree's native memory now instead of when this object is
		collected, which can be long after for a large tree: the collector does
		not see that memory. Its nodes' bindings go with it. Later calls on the
		tree do nothing.
	**/
	public function dispose():Void {
		LayoutTreeNative.blinc_tree_dispose(this.ptr);
	}

	public function createNode():Node {
		var node = new Node(LayoutTreeNative.blinc_tree_create_node(this.ptr));
		@:privateAccess node.tree = this;
		return node;
	}

	public function createTextNode(content:String, fontSize:Single = 16.0, lineHeight:Single = 1.2, wrap:Bool = true, ?fontName:String,
			genericFont:GenericFont = System, fontWeight:Int = 400, italic:Bool = false):TextNode {
		var flags = (wrap ? 1 : 0) | (italic ? 2 : 0);
		var node = new TextNode(LayoutTreeNative.blinc_tree_create_text_node(this.ptr, Utf8.encode(content), Utf8.encode(fontName), fontSize,
			lineHeight, fontWeight, genericFont, flags));
		@:privateAccess node.tree = this;
		return node;
	}

	public inline function addChild(parent:haxe.Int64, child:haxe.Int64):Void {
		LayoutTreeNative.blinc_tree_add_child(this.ptr, parent, child);
	}

	public inline function removeNode(node:haxe.Int64):Void {
		LayoutTreeNative.blinc_tree_remove_node(this.ptr, node);
	}

	public inline function removeSubtree(node:haxe.Int64):Void {
		LayoutTreeNative.blinc_tree_remove_subtree(this.ptr, node);
	}

	/** Puts `next` where `old` is in its parent; `old` is detached, not deleted. **/
	public inline function replaceNode(old:Node, next:Node):Void {
		LayoutTreeNative.blinc_tree_replace_node(this.ptr, old.id, next.id);
	}

	public function replaceChildren(parent:haxe.Int64, children:Array<haxe.Int64>):Void {
		if (children.length == 0) {
			LayoutTreeNative.blinc_tree_clear_children(this.ptr, parent);
			return;
		}
		// Little-endian 64-bit ids, as the native side reads them.
		var ids = new hl.Bytes(children.length * 8);
		for (i in 0...children.length) {
			ids.setI32(i * 8, children[i].low);
			ids.setI32(i * 8 + 4, children[i].high);
		}
		LayoutTreeNative.blinc_tree_replace_children(this.ptr, parent, ids, children.length);
	}

	/**
		Runs the reactions of watches whose values changed, then applies the
		property writes queued since the last flush. True if anything changed
		what is drawn: a watch reacted, or a write moved, resized or restyled
		something, so a window draws a frame.
	**/
	public function flush():Bool {
		var reacted = Watch.runQueued();
		var relayout = LayoutTreeNative.blinc_tree_flush(this.ptr);
		Guard.check();
		// Blinc runs effects inside its flush, so watches it queued there, and
		// what their reactions write, are applied now rather than a frame later.
		while (Watch.runQueued()) {
			reacted = true;
			relayout = LayoutTreeNative.blinc_tree_flush(this.ptr) || relayout;
			Guard.check();
		}
		return reacted || relayout;
	}

	public inline function computeLayout(root:Node, width:Single, height:Single):Void {
		this.root = root;
		LayoutTreeNative.blinc_tree_compute_layout(this.ptr, root.id, width, height);
	}

	/**
		The nodes under `(x, y)` as they are drawn, through transforms and
		inside clips: the topmost first, then each of its ancestors up to
		`root`, each with the point in its own coordinates.
	**/
	public function hitTest(x:Float, y:Float):Array<Hit> {
		if (root == null)
			return [];
		var capacity = 32;
		while (true) {
			var out = new hl.Bytes(capacity * 16);
			var n = LayoutTreeNative.blinc_tree_hit_test(this.ptr, root.id, x, y, out, capacity);
			if (n <= capacity)
				return [
					for (i in 0...n)
						new Hit(haxe.Int64.make(out.getI32(i * 16 + 4), out.getI32(i * 16)), out.getF32(i * 16 + 8), out.getF32(i * 16 + 12))
				];
			capacity = n;
		}
	}

	/** The visible nodes under `root` in document order, as native ids. **/
	public function order():Array<haxe.Int64> {
		if (root == null)
			return [];
		var capacity = 64;
		while (true) {
			var out = new hl.Bytes(capacity * 8);
			var n = LayoutTreeNative.blinc_tree_order(this.ptr, root.id, out, capacity);
			if (n <= capacity)
				return ids(out, n);
			capacity = n;
		}
	}

	/** `node` and its ancestors up to `root`, as native ids; empty when it is not under `root`. **/
	public function path(node:Node):Array<haxe.Int64> {
		if (root == null)
			return [];
		var capacity = 64;
		while (true) {
			var out = new hl.Bytes(capacity * 8);
			var n = LayoutTreeNative.blinc_tree_path(this.ptr, root.id, node.id, out, capacity);
			if (n <= capacity)
				return ids(out, n);
			capacity = n;
		}
	}

	static function ids(out:hl.Bytes, n:Int):Array<haxe.Int64>
		return [for (i in 0...n) haxe.Int64.make(out.getI32(i * 8 + 4), out.getI32(i * 8))];

	/** The node's absolute rectangle, or null before it has been laid out. **/
	public function getBounds(node:Node):Null<Bounds> {
		var out = new hl.Bytes(16);
		if (!LayoutTreeNative.blinc_tree_get_bounds(this.ptr, node.id, out))
			return null;
		return new Bounds(out.getF32(0), out.getF32(4), out.getF32(8), out.getF32(12));
	}
}

/** A node under a point, and the point in its own coordinates. **/
class Hit {
	public final id:haxe.Int64;
	public final x:Float;
	public final y:Float;

	public function new(id:haxe.Int64, x:Float, y:Float) {
		this.id = id;
		this.x = x;
		this.y = y;
	}
}
