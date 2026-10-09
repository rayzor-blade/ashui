package ashui.layout;

import ashui.core.Utf8;
import ashui.core.externs.LayoutTreeNative;
import ashui.reactive.Guard;
import ashui.reactive.Watch;
import ashui.types.Style.GenericFont;

/**
	The tree of nodes a UI is laid out and drawn from. Elements make their
	nodes in it and place them under one another as they are built. Each
	frame, `flush` applies what changed, `computeLayout` lays the nodes
	under a root out at a size, and `DisplayList.update` turns them into
	what to draw; input is hit-tested against the same nodes.

	The nodes live natively, outside the Haxe heap. Haxe refers to each by
	its id, a `haxe.Int64`: a `Node` is a handle holding one, and the
	functions here that take an `Int64` take that id. A program can have any
	number of trees; each is a view onto one native tree kept for the
	process, so a node, its bindings and its queued writes belong to exactly
	one of them. Its nodes are removed when this object is collected, or at
	once with `dispose`.
**/
class LayoutTree {
	/** The native tree, for the functions in `ashui.core.externs` that take one. **/
	public var ptr(default, null):hl.Abstract<"blinc_tree">;

	/** Invalidates pointer hit regions when layout, drawing or handlers change. **/
	@:noCompletion public var hitRevision(default, null) = 0;
	var hitCapacity = 32;
	var hitBytes:Null<hl.Bytes>;

	@:noCompletion public function invalidateHits():Void {
		hitRevision++;
	}

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
		invalidateHits();
		root = null;
		hitBytes = null;
		LayoutTreeNative.blinc_tree_dispose(this.ptr);
	}

	/** A new box node, not yet placed: put it under a parent with `addChild`. **/
	public function createNode():Node {
		var node = new Node(LayoutTreeNative.blinc_tree_create_node(this.ptr));
		@:privateAccess node.tree = this;
		return node;
	}

	/**
		A new node showing `content`, measured with the font given: `fontName`
		by name, or else the `genericFont` family. `wrap` breaks its lines at
		the width it is laid out at.
	**/
	public function createTextNode(content:String, fontSize:Single = 16.0, lineHeight:Single = 1.2, wrap:Bool = true, ?fontName:String,
			genericFont:GenericFont = System, fontWeight:Int = 400, italic:Bool = false):TextNode {
		var flags = (wrap ? 1 : 0) | (italic ? 2 : 0);
		var node = new TextNode(LayoutTreeNative.blinc_tree_create_text_node(this.ptr, Utf8.encode(content), Utf8.encode(fontName), fontSize,
			lineHeight, fontWeight, genericFont, flags));
		@:privateAccess node.tree = this;
		return node;
	}

	// --- Children, and fragments ---
	//
	// A fragment is a node that places its items in its parent, where it
	// stands, instead of laying them out in a box of its own, so they take
	// the parent's direction and gap: what `For` and `Show` (`<for>` and
	// `<if>`) build. The native layout has no such node, so the tree keeps
	// each fragment's items, and the children of each node that holds a
	// fragment, and writes their flattened list as that node's native
	// children whenever either changes. A fragment with no parent holds its
	// items itself.

	/**
		Run at the start of each flush and after each round of reactions in
		it, so what they set is applied in the same flush: how input resolves
		relations, such as an element's group, once the element is placed.
	**/
	public static final flushHooks:Array<LayoutTree->Void> = [];

	/**
		Called with a node whose children are about to change: added, removed,
		replaced or reordered. For a fragment's, it is called for the node the
		fragment is laid out in too, whose laid-out children change with them.
	**/
	public static final childrenHooks:Array<(LayoutTree, haxe.Int64) -> Void> = [];

	function childrenChanged(parent:haxe.Int64):Void {
		invalidateHits();
		if (childrenHooks.length == 0)
			return;
		var at:Null<haxe.Int64> = parent;
		while (at != null) {
			for (hook in childrenHooks)
				hook(this, at);
			at = isFragment(at) ? placedIn.get(key(at)) : null;
		}
	}

	/** The parent of `node`, if it has one, for the hooks above. **/
	function parentOf(node:haxe.Int64):Null<haxe.Int64> {
		if (childrenHooks.length == 0)
			return null;
		var up = ancestors(node);
		return up.length == 0 ? null : up[0];
	}

	final fragments = new Map<String, Fragment>();

	/** The children of nodes that hold a fragment, fragments included. **/
	final placed = new Map<String, Array<haxe.Int64>>();

	/** Where each item of a fragment, and each child of a node in `placed`, is placed. **/
	final placedIn = new Map<String, haxe.Int64>();

	static inline function key(id:haxe.Int64):String
		return '${id.high}:${id.low}';

	/** Makes `node` a fragment: what is added to it is laid out in its parent, in its place. Call before it has children. **/
	public function makeFragment(node:haxe.Int64):Void {
		fragments.set(key(node), new Fragment(node));
	}

	/** Whether `node` was made a fragment. **/
	public function isFragment(node:haxe.Int64):Bool
		return fragments.exists(key(node));

	/** Places `child` last under `parent`; under a fragment, it is laid out in the fragment's parent. **/
	public function addChild(parent:haxe.Int64, child:haxe.Int64):Void {
		childrenChanged(parent);
		var list = fragmentOrPlaced(parent, isFragment(child));
		if (list == null) {
			LayoutTreeNative.blinc_tree_add_child(this.ptr, parent, child);
			ashui.core.Work.notify();
			return;
		}
		list.push(child);
		place(child, parent);
		layoutChildren(parent);
	}

	/** Takes `parent`'s children out from under it without deleting them, so they can be placed elsewhere. **/
	public function detachChildren(parent:haxe.Int64):Void {
		childrenChanged(parent);
		setNative(parent, [], true);
	}

	/** Deletes `node` alone; `removeSubtree` deletes what is below it too. **/
	public function removeNode(node:haxe.Int64):Void {
		invalidateHits();
		var parent = parentOf(node);
		if (parent != null)
			childrenChanged(parent);
		unplace(node);
		LayoutTreeNative.blinc_tree_remove_node(this.ptr, node);
		ashui.core.Work.notify();
	}

	/** Deletes `node` and everything below it, a fragment's items included. **/
	public function removeSubtree(node:haxe.Int64):Void {
		invalidateHits();
		var parent = parentOf(node);
		if (parent != null)
			childrenChanged(parent);
		var f = fragments.get(key(node));
		if (f != null) {
			for (item in f.items.copy())
				removeSubtree(item);
			fragments.remove(key(node));
		}
		placed.remove(key(node));
		unplace(node);
		LayoutTreeNative.blinc_tree_remove_subtree(this.ptr, node);
		ashui.core.Work.notify();
	}

	/** Puts `next` where `old` is in its parent; `old` is detached, not deleted. **/
	public function replaceNode(old:Node, next:Node):Void {
		invalidateHits();
		var changed = parentOf(old.id);
		if (changed != null)
			childrenChanged(changed);
		var parent = placedIn.get(key(old.id));
		if (parent == null) {
			LayoutTreeNative.blinc_tree_replace_node(this.ptr, old.id, next.id);
			ashui.core.Work.notify();
			return;
		}
		var list = listOf(parent);
		list[list.indexOf(old.id)] = next.id;
		placedIn.remove(key(old.id));
		place(next.id, parent);
		layoutChildren(parent);
	}

	/** Makes `children` `parent`'s children, in order; with none, deletes what it had. **/
	public function replaceChildren(parent:haxe.Int64, children:Array<haxe.Int64>):Void {
		childrenChanged(parent);
		var holdsFragment = Lambda.exists(children, isFragment);
		var list = fragmentOrPlaced(parent, holdsFragment);
		if (list == null) {
			setNative(parent, children, false);
			return;
		}
		if (children.length == 0) {
			for (child in list.copy())
				removeSubtree(child);
			return;
		}
		for (child in list)
			if (children.indexOf(child) < 0)
				placedIn.remove(key(child));
		list.resize(0);
		for (child in children) {
			list.push(child);
			place(child, parent);
		}
		layoutChildren(parent);
	}

	/**
		`parent`'s list of children kept here: a fragment's items, or the
		children of a node holding a fragment. When `adding` a fragment to a
		node that has none yet, its list starts from its native children.
		Null when it is kept natively alone.
	**/
	function fragmentOrPlaced(parent:haxe.Int64, adding:Bool):Null<Array<haxe.Int64>> {
		var f = fragments.get(key(parent));
		if (f != null)
			return f.items;
		var list = placed.get(key(parent));
		if (list == null && adding) {
			list = nativeChildren(parent);
			placed.set(key(parent), list);
			for (child in list)
				placedIn.set(key(child), parent);
		}
		return list;
	}

	function listOf(parent:haxe.Int64):Array<haxe.Int64> {
		var f = fragments.get(key(parent));
		return f != null ? f.items : placed.get(key(parent));
	}

	function place(child:haxe.Int64, parent:haxe.Int64):Void {
		placedIn.set(key(child), parent);
		var f = fragments.get(key(child));
		if (f != null && f.parent == null) {
			// Its items move from its own node into the parent's.
			f.parent = parent;
			setNative(child, [], true);
		}
	}

	/** Takes `node` out of the list it is placed in, if any; what is native follows by itself. **/
	function unplace(node:haxe.Int64):Void {
		var parent = placedIn.get(key(node));
		if (parent == null)
			return;
		placedIn.remove(key(node));
		var list = listOf(parent);
		if (list != null)
			list.remove(node);
	}

	/**
		Writes the flattened children of the node that lays out `parent`'s
		list: the nearest one up that is not a fragment, or the topmost
		fragment while it has no parent.
	**/
	function layoutChildren(parent:haxe.Int64):Void {
		var host = parent;
		var f = fragments.get(key(host));
		while (f != null && f.parent != null) {
			host = f.parent;
			f = fragments.get(key(host));
		}
		var flat = [];
		flatten(listOf(host), flat);
		setNative(host, flat, true);
	}

	function flatten(list:Array<haxe.Int64>, out:Array<haxe.Int64>):Void {
		for (id in list) {
			var f = fragments.get(key(id));
			if (f != null)
				flatten(f.items, out);
			else
				out.push(id);
		}
	}

	/** Sets `parent`'s native children; with none, deletes those it had unless `detach`. **/
	function setNative(parent:haxe.Int64, children:Array<haxe.Int64>, detach:Bool):Void {
		if (children.length == 0 && !detach) {
			LayoutTreeNative.blinc_tree_clear_children(this.ptr, parent);
			ashui.core.Work.notify();
			return;
		}
		// Little-endian 64-bit ids, as the native side reads them.
		var ids = new hl.Bytes(children.length * 8 + 8);
		for (i in 0...children.length) {
			ids.setI32(i * 8, children[i].low);
			ids.setI32(i * 8 + 4, children[i].high);
		}
		if (detach)
			LayoutTreeNative.blinc_tree_set_children(this.ptr, parent, ids, children.length);
		else
			LayoutTreeNative.blinc_tree_replace_children(this.ptr, parent, ids, children.length);
		ashui.core.Work.notify();
	}

	function nativeChildren(node:haxe.Int64):Array<haxe.Int64>
		return children(node);

	/** `node`'s children as laid out, a fragment's items in its place, as native ids. **/
	public function children(node:haxe.Int64):Array<haxe.Int64> {
		var capacity = 16;
		while (true) {
			var out = new hl.Bytes(capacity * 8);
			var n = LayoutTreeNative.blinc_tree_children(this.ptr, node, out, capacity);
			if (n <= capacity)
				return ids(out, n);
			capacity = n;
		}
	}

	/** `node`'s ancestors as laid out, the parent first, as native ids; fragments are not among them. **/
	public function ancestors(node:haxe.Int64):Array<haxe.Int64> {
		var capacity = 16;
		while (true) {
			var out = new hl.Bytes(capacity * 8);
			var n = LayoutTreeNative.blinc_tree_ancestors(this.ptr, node, out, capacity);
			if (n <= capacity)
				return ids(out, n);
			capacity = n;
		}
	}

	/**
		Runs the reactions of watches whose values changed, then applies the
		property writes queued since the last flush. True if anything changed
		what is drawn: a watch reacted, or a write moved, resized or restyled
		something, so a window draws a frame.
	**/
	public function flush():Bool {
		for (hook in flushHooks)
			hook(this);
		var reacted = Watch.runQueued();
		for (hook in flushHooks)
			hook(this);
		var relayout = LayoutTreeNative.blinc_tree_flush(this.ptr);
		Guard.check();
		// The native flush runs watches' `read`s, so watches it queued there,
		// and what their reactions write, are applied now rather than a frame
		// later.
		while (Watch.runQueued()) {
			reacted = true;
			for (hook in flushHooks)
				hook(this);
			relayout = LayoutTreeNative.blinc_tree_flush(this.ptr) || relayout;
			Guard.check();
		}
		var drawn = drawnChanged;
		drawnChanged = false;
		var changed = reacted || relayout || drawn;
		if (changed)
			invalidateHits();
		return changed;
	}

	/** Set by what changes the drawing outside the queued writes, as a scroll or a layout animation's visual does. **/
	var drawnChanged = false;

	/** Something drawn changed outside the queued property writes: the next `flush` reports a change, so a frame is drawn. **/
	public function markDrawn():Void {
		invalidateHits();
		drawnChanged = true;
		ashui.core.Work.notify();
	}

	/**
		Whether any of `node`'s box is on screen: inside the root, and inside
		every box that clips it, scrolled as they are. A node under a transform
		counts as in view.
	**/
	public function inView(node:haxe.Int64):Bool
		return LayoutTreeNative.blinc_tree_in_view(this.ptr, node);

	/**
		Lays out the nodes under `root` in `width` by `height` layout units,
		and makes `root` the node input is hit-tested under.
	**/
	public function computeLayout(root:Node, width:Single, height:Single):Void {
		invalidateHits();
		this.root = root;
		LayoutTreeNative.blinc_tree_compute_layout(this.ptr, root.id, width, height);
		// What sizes itself from the layout, as text flow from its width, lays out again until nothing does.
		for (_ in 0...LAYOUT_PASSES) {
			var changed = false;
			for (hook in layoutHooks)
				if (hook(this))
					changed = true;
			if (!changed)
				break;
			flush();
			LayoutTreeNative.blinc_tree_compute_layout(this.ptr, root.id, width, height);
		}
		for (hook in settledHooks)
			hook(this);
	}

	/** Passes after the first that `layoutHooks` may ask for; text flow needs one when a width changes. **/
	static inline var LAYOUT_PASSES = 3;

	/** Called after each layout pass; true when it changed what is laid out, for another pass. **/
	public static final layoutHooks:Array<LayoutTree->Bool> = [];

	/** Called once a layout has settled, after its last pass: what reads the final layout, as layout animation does, never sees a pass between. **/
	public static final settledHooks:Array<LayoutTree->Void> = [];

	/** `node`'s own text alignment, as `ashui.types.Style.TextAlign`'s codes, set by CSS, Tw or its own code; -1 when it has none. **/
	public function textAlign(node:haxe.Int64):Int
		return LayoutTreeNative.blinc_tree_text_align(this.ptr, node);

	/**
		Draws `node` moved by `(dx, dy)` from where layout puts it, and at
		`width` by `height` with its children clipped to that when `width` is
		not negative, as a layout animation does; its children move with it,
		and `hitTest` finds it there. Layout is not touched.
	**/
	public function setVisual(node:haxe.Int64, dx:Float, dy:Float, width:Float = -1, height:Float = -1):Void {
		invalidateHits();
		LayoutTreeNative.blinc_tree_set_visual(this.ptr, node, dx, dy, width, height, false);
		drawnChanged = true;
		ashui.core.Work.notify();
	}

	/** Draws `node` where layout puts it again. **/
	public function clearVisual(node:haxe.Int64):Void {
		invalidateHits();
		LayoutTreeNative.blinc_tree_set_visual(this.ptr, node, 0, 0, -1, -1, true);
		drawnChanged = true;
		ashui.core.Work.notify();
	}

	/** Draws `node` as `notch`, or as its box again with null. **/
	public function setNotch(node:haxe.Int64, notch:Null<ashui.types.Notch>):Void {
		drawnChanged = true;
		if (notch == null) {
			LayoutTreeNative.blinc_tree_set_notch(this.ptr, node, null);
			ashui.core.Work.notify();
			return;
		}
		var values = notch.encode();
		var bytes = new hl.Bytes(values.length * 4);
		for (i => v in values)
			bytes.setF32(i * 4, v);
		LayoutTreeNative.blinc_tree_set_notch(this.ptr, node, bytes);
		ashui.core.Work.notify();
	}

	/** Makes `hitTest` pass through `node` and everything inside it, as CSS's `pointer-events: none`, or not. **/
	public function setPassThrough(node:haxe.Int64, through:Bool):Void {
		LayoutTreeNative.blinc_tree_set_pass_through(this.ptr, node, through);
		markDrawn();
	}

	/** `node`'s padding as laid out, and whether it paints a box of its own: a background, a border or a shadow. **/
	public function boxEdges(node:haxe.Int64):Null<{top:Float, right:Float, bottom:Float, left:Float, painted:Bool}> {
		var out = new hl.Bytes(20);
		if (!LayoutTreeNative.blinc_tree_box_edges(this.ptr, node, out))
			return null;
		return {top: out.getF32(0), right: out.getF32(4), bottom: out.getF32(8), left: out.getF32(12), painted: out.getF32(16) != 0};
	}

	/**
		The nodes under `(x, y)` as they are drawn, through transforms and
		inside clips: the topmost first, then each of its ancestors up to
		`root`, each with the point in its own coordinates.

		With `region`, also writes four F32s (left, top, right, bottom) where
		the hit path stays the same until `hitRevision` changes. Zero bounds
		mean the point needs an exact hit test, as near a transformed edge.
	**/
	public function hitTest(x:Float, y:Float, ?region:hl.Bytes):Array<Hit> {
		if (root == null) {
			if (region != null)
				for (i in 0...4)
					region.setF32(i * 4, 0);
			return [];
		}
		if (hitBytes == null)
			hitBytes = new hl.Bytes(hitCapacity * 16);
		while (true) {
			var n = region == null
				? LayoutTreeNative.blinc_tree_hit_test(this.ptr, root.id, x, y, hitBytes, hitCapacity)
				: LayoutTreeNative.blinc_tree_hit_test_region(this.ptr, root.id, x, y, hitBytes, hitCapacity, region);
			if (n <= hitCapacity)
				return [for (i in 0...n) new Hit(haxe.Int64.make(hitBytes.getI32(i * 16 + 4), hitBytes.getI32(i * 16)),
					hitBytes.getF32(i * 16 + 8), hitBytes.getF32(i * 16 + 12))];
			hitCapacity = n;
			hitBytes = new hl.Bytes(hitCapacity * 16);
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

/** A fragment's items, in order, and the node it is placed in once it is. **/
private class Fragment {
	public final id:haxe.Int64;
	public final items:Array<haxe.Int64> = [];
	public var parent:Null<haxe.Int64> = null;

	public function new(id:haxe.Int64)
		this.id = id;
}
