package ashui.layout;

import ashui.core.Utf8;
import ashui.core.externs.LayoutTreeNative;
import ashui.reactive.Guard;
import ashui.reactive.Watch;
import ashui.types.Style.GenericFont;

/**
	A Blinc layout tree. Its native memory is released when this object is
	collected.

	Blinc queues every property write for the whole process, so a program has
	one tree: `flush` applies the queue to the tree it is called on.
**/
class LayoutTree {
	public var ptr(default, null):hl.Abstract<"blinc_tree">;

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
		property writes queued since the last flush. True if anything needs a
		relayout.
	**/
	public function flush():Bool {
		var reacted = Watch.runQueued();
		var relayout = LayoutTreeNative.blinc_tree_flush(this.ptr);
		Guard.check();
		return reacted || relayout;
	}

	public inline function computeLayout(root:Node, width:Single, height:Single):Void {
		LayoutTreeNative.blinc_tree_compute_layout(this.ptr, root.id, width, height);
	}

	/** The node's absolute rectangle, or null before it has been laid out. **/
	public function getBounds(node:Node):Null<Bounds> {
		var out = new hl.Bytes(16);
		if (!LayoutTreeNative.blinc_tree_get_bounds(this.ptr, node.id, out))
			return null;
		return new Bounds(out.getF32(0), out.getF32(4), out.getF32(8), out.getF32(12));
	}
}
