package ashui.core.externs;

/**
	The layout tree in `blinc_abi.hdll`. Node ids are Blinc's 64-bit
	`LayoutNodeId`s and are only meaningful within their tree.
**/
@:hlNative("blinc_abi")
extern class LayoutTreeNative {
	static function blinc_tree_new():hl.Abstract<"blinc_tree">;

	/** Frees the tree now and unbinds its nodes; later calls on it do nothing. **/
	static function blinc_tree_dispose(tree:hl.Abstract<"blinc_tree">):Void;

	static function blinc_tree_create_node(tree:hl.Abstract<"blinc_tree">):haxe.Int64;

	/** `flags`: bit 0 wrap, bit 1 italic. **/
	static function blinc_tree_create_text_node(tree:hl.Abstract<"blinc_tree">, content:hl.Bytes, fontName:hl.Bytes, fontSize:Single,
		lineHeight:Single, fontWeight:Int, genericFont:Int, flags:Int):haxe.Int64;

	static function blinc_tree_add_child(tree:hl.Abstract<"blinc_tree">, parent:haxe.Int64, child:haxe.Int64):Void;
	static function blinc_tree_remove_node(tree:hl.Abstract<"blinc_tree">, node:haxe.Int64):Void;
	static function blinc_tree_remove_subtree(tree:hl.Abstract<"blinc_tree">, node:haxe.Int64):Void;
	static function blinc_tree_clear_children(tree:hl.Abstract<"blinc_tree">, parent:haxe.Int64):Void;

	/** `children` holds `len` consecutive 64-bit ids. **/
	static function blinc_tree_replace_children(tree:hl.Abstract<"blinc_tree">, parent:haxe.Int64, children:hl.Bytes, len:Int):Void;

	/** Applies queued property writes; true if any needs a relayout. **/
	static function blinc_tree_flush(tree:hl.Abstract<"blinc_tree">):Bool;

	static function blinc_tree_compute_layout(tree:hl.Abstract<"blinc_tree">, root:haxe.Int64, width:Single, height:Single):Void;

	/** Writes absolute x, y, width, height as four F32s into `out`. **/
	static function blinc_tree_get_bounds(tree:hl.Abstract<"blinc_tree">, node:haxe.Int64, out:hl.Bytes):Bool;
}
