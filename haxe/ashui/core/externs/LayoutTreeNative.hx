package ashui.core.externs;

/**
	The layout tree in the native library, `blinc_abi.hdll`: the nodes, their
	styles, flexbox and grid layout, and the display list drawn from them.
	`ashui.layout.LayoutTree` and `Node` wrap these calls. Node ids are
	64-bit and only meaningful within their tree.
**/
@:hlNative("blinc_abi")
extern class LayoutTreeNative {
	/** A new, empty tree. **/
	static function blinc_tree_new():hl.Abstract<"blinc_tree">;

	/** Frees the tree now and unbinds its nodes; later calls on it do nothing. **/
	static function blinc_tree_dispose(tree:hl.Abstract<"blinc_tree">):Void;

	/** A new node with no parent and default style; its id. **/
	static function blinc_tree_create_node(tree:hl.Abstract<"blinc_tree">):haxe.Int64;

	/** A new node that draws `content` in the given font; its id. `flags`: bit 0 wrap, bit 1 italic. **/
	static function blinc_tree_create_text_node(tree:hl.Abstract<"blinc_tree">, content:hl.Bytes, fontName:hl.Bytes, fontSize:Single,
		lineHeight:Single, fontWeight:Int, genericFont:Int, flags:Int):haxe.Int64;

	static function blinc_tree_add_child(tree:hl.Abstract<"blinc_tree">, parent:haxe.Int64, child:haxe.Int64):Void;
	static function blinc_tree_remove_node(tree:hl.Abstract<"blinc_tree">, node:haxe.Int64):Void;
	static function blinc_tree_remove_subtree(tree:hl.Abstract<"blinc_tree">, node:haxe.Int64):Void;
	static function blinc_tree_clear_children(tree:hl.Abstract<"blinc_tree">, parent:haxe.Int64):Void;

	/** Puts `next` where `old` is among its parent's children; `old` is detached, not deleted. **/
	static function blinc_tree_replace_node(tree:hl.Abstract<"blinc_tree">, old:haxe.Int64, next:haxe.Int64):Void;

	/** `children` holds `len` consecutive 64-bit ids. **/
	static function blinc_tree_replace_children(tree:hl.Abstract<"blinc_tree">, parent:haxe.Int64, children:hl.Bytes, len:Int):Void;

	/** Writes `node`'s ancestors, the parent first, as 64-bit ids, at most `capacity`; returns how many there are. **/
	static function blinc_tree_ancestors(tree:hl.Abstract<"blinc_tree">, node:haxe.Int64, out:hl.Bytes, capacity:Int):Int;

	/** Writes `node`'s children as 64-bit ids, at most `capacity`; returns how many there are. **/
	static function blinc_tree_children(tree:hl.Abstract<"blinc_tree">, node:haxe.Int64, out:hl.Bytes, capacity:Int):Int;

	/** Makes the `len` ids in `children` `parent`'s children, detaching, not deleting, the rest. **/
	static function blinc_tree_set_children(tree:hl.Abstract<"blinc_tree">, parent:haxe.Int64, children:hl.Bytes, len:Int):Void;

	/** Applies queued property writes; true if any changed what is drawn, by layout or by look. **/
	static function blinc_tree_flush(tree:hl.Abstract<"blinc_tree">):Bool;

	/** Lays out the nodes under `root` in a `width` × `height` box. **/
	static function blinc_tree_compute_layout(tree:hl.Abstract<"blinc_tree">, root:haxe.Int64, width:Single, height:Single):Void;

	/**
		Packs the primitives to draw under `root` into `out`, at most
		`capacity` records (see `DisplayList`). `params` is eight F32s: the
		device pixels per layout unit text is rasterized for; the theme's
		corner `n` (0 for no smoothing), smoothing threshold and full radius;
		and the straight RGBA colour of text that neither it nor an ancestor
		sets. Returns how many there are, which may be more than were written.
	**/
	static function blinc_tree_display_list(tree:hl.Abstract<"blinc_tree">, root:haxe.Int64, params:hl.Bytes, out:hl.Bytes, capacity:Int):Int;

	/** Makes `node` draw image `slot`, which the renderer resolves, in its content box; a negative slot stops it. **/
	static function blinc_tree_set_image(tree:hl.Abstract<"blinc_tree">, node:haxe.Int64, slot:Int):Void;

	/**
		Writes the nodes under `(x, y)`, the topmost first and then its
		ancestors up to `root`, into `out` as 16-byte records: the 64-bit id
		and the point in that node's coordinates as two F32s. At most
		`capacity`; returns how many there are.
	**/
	static function blinc_tree_hit_test(tree:hl.Abstract<"blinc_tree">, root:haxe.Int64, x:Single, y:Single, out:hl.Bytes, capacity:Int):Int;

	/** Writes the visible nodes under `root` in document order as 64-bit ids, at most `capacity`; returns how many there are. **/
	static function blinc_tree_order(tree:hl.Abstract<"blinc_tree">, root:haxe.Int64, out:hl.Bytes, capacity:Int):Int;

	/** Writes `node` and its ancestors up to `root` as 64-bit ids, at most `capacity`; 0 when `node` is not under `root`. **/
	static function blinc_tree_path(tree:hl.Abstract<"blinc_tree">, root:haxe.Int64, node:haxe.Int64, out:hl.Bytes, capacity:Int):Int;

	/** Scrolls container `node`'s content by `(x, y)` and colours its thumb `thumb`, `0xAARRGGBB`; 0 hides it. **/
	static function blinc_tree_set_scroll(tree:hl.Abstract<"blinc_tree">, node:haxe.Int64, x:Single, y:Single, thumb:Int):Void;

	/** Writes container `node`'s viewport width and height and its content's width and height as four F32s; false before layout. **/
	static function blinc_tree_scroll_extent(tree:hl.Abstract<"blinc_tree">, node:haxe.Int64, out:hl.Bytes):Bool;

	/** Makes the hit test pass through `node` and everything inside it, as CSS's `pointer-events: none`, or not. **/
	static function blinc_tree_set_pass_through(tree:hl.Abstract<"blinc_tree">, node:haxe.Int64, through:Bool):Void;

	/** Writes absolute x, y, width, height as four F32s into `out`. **/
	static function blinc_tree_get_bounds(tree:hl.Abstract<"blinc_tree">, node:haxe.Int64, out:hl.Bytes):Bool;
}
