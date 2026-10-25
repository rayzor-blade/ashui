package ashui.core.externs;

import ashui.core.externs.Handles;

#if ashui_caribou
/** `LayoutTreeNative` over the `blinc_abi` Caribou plugin's `Tree`. **/
class LayoutTreeNative {
	static inline function text(b:hl.Bytes):String
		return b == null ? "" : @:privateAccess String.fromUTF8(b);

	static inline function wrap(b:hl.Bytes, length:Int):haxe.io.Bytes
		return b == null ? haxe.io.Bytes.alloc(0) : @:privateAccess new haxe.io.Bytes(b, length);

	public static inline function blinc_tree_new():TreeHandle
		return new blinc_abi.Tree();

	public static inline function blinc_tree_dispose(tree:TreeHandle):Void
		tree.dispose();

	public static inline function blinc_tree_create_node(tree:TreeHandle):haxe.Int64
		return tree.create_node();

	public static inline function blinc_tree_create_text_node(tree:TreeHandle, content:hl.Bytes, fontName:hl.Bytes, fontSize:Single, lineHeight:Single,
			fontWeight:Int, genericFont:Int, flags:Int):haxe.Int64
		return tree.create_text_node(text(content), text(fontName), fontSize, lineHeight, fontWeight, genericFont, flags);

	public static inline function blinc_tree_add_child(tree:TreeHandle, parent:haxe.Int64, child:haxe.Int64):Void
		tree.add_child(parent, child);

	public static inline function blinc_tree_remove_node(tree:TreeHandle, node:haxe.Int64):Void
		tree.remove_node(node);

	public static inline function blinc_tree_remove_subtree(tree:TreeHandle, node:haxe.Int64):Void
		tree.remove_subtree(node);

	public static inline function blinc_tree_clear_children(tree:TreeHandle, parent:haxe.Int64):Void
		tree.clear_children(parent);

	public static inline function blinc_tree_replace_node(tree:TreeHandle, old:haxe.Int64, next:haxe.Int64):Void
		tree.replace_node(old, next);

	public static inline function blinc_tree_replace_children(tree:TreeHandle, parent:haxe.Int64, children:hl.Bytes, len:Int):Void
		tree.replace_children(parent, wrap(children, len * 8));

	public static inline function blinc_tree_ancestors(tree:TreeHandle, node:haxe.Int64, out:hl.Bytes, capacity:Int):Int
		return tree.ancestors(node, wrap(out, capacity * 8));

	public static inline function blinc_tree_children(tree:TreeHandle, node:haxe.Int64, out:hl.Bytes, capacity:Int):Int
		return tree.children(node, wrap(out, capacity * 8));

	public static inline function blinc_tree_set_children(tree:TreeHandle, parent:haxe.Int64, children:hl.Bytes, len:Int):Void
		tree.set_children(parent, wrap(children, len * 8));

	public static inline function blinc_tree_set_grid_rows(tree:TreeHandle, group:haxe.Int64, rows:hl.Bytes, len:Int):Bool
		return tree.set_grid_rows(group, wrap(rows, len * 8));

	public static inline function blinc_tree_flush(tree:TreeHandle):Bool
		return tree.flush();

	public static inline function blinc_tree_compute_layout(tree:TreeHandle, root:haxe.Int64, width:Single, height:Single):Void
		tree.compute_layout(root, width, height);

	public static inline function blinc_tree_display_list(tree:TreeHandle, root:haxe.Int64, params:hl.Bytes, out:hl.Bytes, capacity:Int):Int
		return tree.display_list(root, wrap(params, 36), wrap(out, capacity * ashui.layout.DisplayList.RECORD_BYTES));

	public static inline function blinc_tree_set_image(tree:TreeHandle, node:haxe.Int64, slot:Int):Void
		tree.set_image(node, slot);

	public static inline function blinc_tree_set_image_mapping(tree:TreeHandle, node:haxe.Int64, fit:Int, x:Single, y:Single, offsetX:Single,
			offsetY:Single):Void
		tree.set_image_mapping(node, fit, x, y, offsetX, offsetY);

	public static inline function blinc_tree_set_canvas(tree:TreeHandle, node:haxe.Int64, slot:Int):Void
		tree.set_canvas(node, slot);

	public static inline function blinc_tree_hit_test_region(tree:TreeHandle, root:haxe.Int64, x:Single, y:Single, out:hl.Bytes, capacity:Int,
			region:hl.Bytes):Int
		return tree.hit_test_region(root, x, y, wrap(out, capacity * 16), wrap(region, 16));

	public static inline function blinc_tree_hit_test(tree:TreeHandle, root:haxe.Int64, x:Single, y:Single, out:hl.Bytes, capacity:Int):Int
		return tree.hit_test(root, x, y, wrap(out, capacity * 16));

	public static inline function blinc_tree_order(tree:TreeHandle, root:haxe.Int64, out:hl.Bytes, capacity:Int):Int
		return tree.order(root, wrap(out, capacity * 8));

	public static inline function blinc_tree_path(tree:TreeHandle, root:haxe.Int64, node:haxe.Int64, out:hl.Bytes, capacity:Int):Int
		return tree.path(root, node, wrap(out, capacity * 8));

	public static inline function blinc_tree_set_scroll(tree:TreeHandle, node:haxe.Int64, x:Single, y:Single, thumb:Int):Void
		tree.set_scroll(node, x, y, thumb);

	public static inline function blinc_tree_set_scrollbar_style(tree:TreeHandle, node:haxe.Int64, width:Single, track:Int):Void
		tree.set_scrollbar_style(node, width, track);

	public static inline function blinc_tree_scroll_extent(tree:TreeHandle, node:haxe.Int64, out:hl.Bytes):Bool
		return tree.scroll_extent(node, wrap(out, 16));

	public static inline function blinc_tree_box_edges(tree:TreeHandle, node:haxe.Int64, out:hl.Bytes):Bool
		return tree.box_edges(node, wrap(out, 20));

	public static inline function blinc_tree_text_align(tree:TreeHandle, node:haxe.Int64):Int
		return tree.text_align(node);

	public static inline function blinc_tree_text_limits(tree:TreeHandle, node:haxe.Int64, out:hl.Bytes):Void
		tree.text_limits(node, wrap(out, 8));

	public static inline function blinc_tree_set_visual(tree:TreeHandle, node:haxe.Int64, dx:Single, dy:Single, w:Single, h:Single, clear:Bool):Void
		tree.set_visual(node, dx, dy, w, h, clear);

	public static inline function blinc_tree_set_notch(tree:TreeHandle, node:haxe.Int64, data:hl.Bytes):Void
		tree.set_notch(node, wrap(data, 48));

	public static inline function blinc_tree_set_pass_through(tree:TreeHandle, node:haxe.Int64, through:Bool):Void
		tree.set_pass_through(node, through);

	public static inline function blinc_tree_get_bounds(tree:TreeHandle, node:haxe.Int64, out:hl.Bytes):Bool
		return tree.get_bounds(node, wrap(out, 16));

	public static inline function blinc_tree_get_box(tree:TreeHandle, node:haxe.Int64, out:hl.Bytes):Bool
		return tree.get_box(node, wrap(out, 48));

	public static inline function blinc_tree_in_view(tree:TreeHandle, node:haxe.Int64):Bool
		return tree.in_view(node);
}
#else
/**
	The layout tree in the native library, `blinc_abi.hdll`: the nodes, their
	styles, flexbox and grid layout, and the display list drawn from them.
	`ashui.layout.LayoutTree` and `Node` wrap these calls. Node ids are
	64-bit and only meaningful within their tree.
**/
@:hlNative("blinc_abi")
extern class LayoutTreeNative {
	/** A new, empty tree. **/
	static function blinc_tree_new():TreeHandle;

	/** Frees the tree now and unbinds its nodes; later calls on it do nothing. **/
	static function blinc_tree_dispose(tree:TreeHandle):Void;

	/** A new node with no parent and default style; its id. **/
	static function blinc_tree_create_node(tree:TreeHandle):haxe.Int64;

	/** A new node that draws `content` in the given font; its id. `flags`: bit 0 wrap, bit 1 italic. **/
	static function blinc_tree_create_text_node(tree:TreeHandle, content:hl.Bytes, fontName:hl.Bytes, fontSize:Single, lineHeight:Single,
		fontWeight:Int, genericFont:Int, flags:Int):haxe.Int64;

	static function blinc_tree_add_child(tree:TreeHandle, parent:haxe.Int64, child:haxe.Int64):Void;
	static function blinc_tree_remove_node(tree:TreeHandle, node:haxe.Int64):Void;
	static function blinc_tree_remove_subtree(tree:TreeHandle, node:haxe.Int64):Void;
	static function blinc_tree_clear_children(tree:TreeHandle, parent:haxe.Int64):Void;

	/** Puts `next` where `old` is among its parent's children; `old` is detached, not deleted. **/
	static function blinc_tree_replace_node(tree:TreeHandle, old:haxe.Int64, next:haxe.Int64):Void;

	/** `children` holds `len` consecutive 64-bit ids. **/
	static function blinc_tree_replace_children(tree:TreeHandle, parent:haxe.Int64, children:hl.Bytes, len:Int):Void;

	/** Writes `node`'s ancestors, the parent first, as 64-bit ids, at most `capacity`; returns how many there are. **/
	static function blinc_tree_ancestors(tree:TreeHandle, node:haxe.Int64, out:hl.Bytes, capacity:Int):Int;

	/** Writes authored children as 64-bit ids; CSS order does not change them. git-bug: 7977648 / ABI 62aa0b0. **/
	static function blinc_tree_children(tree:TreeHandle, node:haxe.Int64, out:hl.Bytes, capacity:Int):Int;

	/** Makes the `len` ids in `children` `parent`'s children, detaching, not deleting, the rest. **/
	static function blinc_tree_set_children(tree:TreeHandle, parent:haxe.Int64, children:hl.Bytes, len:Int):Void;

	/** Shared row layout/paint with authored cell parents retained; empty rows reset. git-bug: 471d54e / ABI bcec1a0. **/
	static function blinc_tree_set_grid_rows(tree:TreeHandle, group:haxe.Int64, rows:hl.Bytes, len:Int):Bool;

	/** Applies queued property writes; true if any changed what is drawn, by layout or by look. **/
	static function blinc_tree_flush(tree:TreeHandle):Bool;

	/** Lays out the nodes under `root` in a `width` × `height` box. **/
	static function blinc_tree_compute_layout(tree:TreeHandle, root:haxe.Int64, width:Single, height:Single):Void;

	/**
		Packs the primitives to draw under `root` into `out`, at most
		`capacity` records (see `DisplayList`). `params` is eight F32s: the
		device pixels per layout unit text is rasterized for; the theme's
		corner `n` (0 for no smoothing), smoothing threshold and full radius;
		and the straight RGBA colour of text that neither it nor an ancestor
		sets. Returns how many there are, which may be more than were written.
	**/
	static function blinc_tree_display_list(tree:TreeHandle, root:haxe.Int64, params:hl.Bytes, out:hl.Bytes, capacity:Int):Int;

	/** Makes `node` draw image `slot`, which the renderer resolves, in its content box; a negative slot stops it. **/
	static function blinc_tree_set_image(tree:TreeHandle, node:haxe.Int64, slot:Int):Void;

	/** Optional bitmap fit/object-position, free-space fractions plus pixel offsets. git-bug: a8ca996 / ABI 4d9ea6a. **/
	static function blinc_tree_set_image_mapping(tree:TreeHandle, node:haxe.Int64, fit:Int, x:Single, y:Single, offsetX:Single,
		offsetY:Single):Void;

	static function blinc_tree_set_canvas(tree:TreeHandle, node:haxe.Int64, slot:Int):Void;

	/**
		Writes the nodes under `(x, y)`, the topmost first and then its
		ancestors up to `root`, into `out` as 16-byte records: the 64-bit id
		and the point in that node's coordinates as two F32s. At most
		`capacity`; returns how many there are.
	**/
	static function blinc_tree_hit_test_region(tree:TreeHandle, root:haxe.Int64, x:Single, y:Single, out:hl.Bytes, capacity:Int,
		region:hl.Bytes):Int;

	static function blinc_tree_hit_test(tree:TreeHandle, root:haxe.Int64, x:Single, y:Single, out:hl.Bytes, capacity:Int):Int;

	/** Visible nodes in authored document order, independent of CSS order/z-index. git-bug: 7977648 / ABI 62aa0b0. **/
	static function blinc_tree_order(tree:TreeHandle, root:haxe.Int64, out:hl.Bytes, capacity:Int):Int;

	/** Writes `node` and its ancestors up to `root` as 64-bit ids, at most `capacity`; 0 when `node` is not under `root`. **/
	static function blinc_tree_path(tree:TreeHandle, root:haxe.Int64, node:haxe.Int64, out:hl.Bytes, capacity:Int):Int;

	/** Scrolls container `node`'s content by `(x, y)` and colours its thumb `thumb`, `0xAARRGGBB`; 0 hides it. **/
	static function blinc_tree_set_scroll(tree:TreeHandle, node:haxe.Int64, x:Single, y:Single, thumb:Int):Void;

	/** Overlay scrollbar width and 0xAARRGGBB track; zero hides both. git-bug: 4512d6f / ABI a00b6d0. **/
	static function blinc_tree_set_scrollbar_style(tree:TreeHandle, node:haxe.Int64, width:Single, track:Int):Void;

	/** Writes container `node`'s viewport width and height and its content's width and height as four F32s; false before layout. **/
	static function blinc_tree_scroll_extent(tree:TreeHandle, node:haxe.Int64, out:hl.Bytes):Bool;

	/** Writes padding, top, right, bottom, left, then 1 if the node paints a box of its own and 0 if not, as five F32s; false before layout. **/
	static function blinc_tree_box_edges(tree:TreeHandle, node:haxe.Int64, out:hl.Bytes):Bool;

	/** `node`'s own text alignment, as `ashui.types.Style.TextAlign`'s codes; -1 when it has none. **/
	static function blinc_tree_text_align(tree:TreeHandle, node:haxe.Int64):Int;

	/** Nearest limits: line count (0 none), overflow (-1 undeclared, 0 clip, 1 ellipsis). git-bug: 6812621. **/
	static function blinc_tree_text_limits(tree:TreeHandle, node:haxe.Int64, out:hl.Bytes):Void;

	/** Draws `node` moved by `(dx, dy)` from its layout, at size `(w, h)` when `w` is not negative, its children clipped to it; `clear` puts it back. **/
	static function blinc_tree_set_visual(tree:TreeHandle, node:haxe.Int64, dx:Single, dy:Single, w:Single, h:Single, clear:Bool):Void;

	/** Draws `node` as a notch from twelve F32s, or as a box again with null (see `ashui.types.Notch.encode`). **/
	static function blinc_tree_set_notch(tree:TreeHandle, node:haxe.Int64, data:hl.Bytes):Void;

	/** Subtree pointer pass-through; descendants cannot override it. git-bug: 4512d6f / 8780d6b, ABI a00b6d0. **/
	static function blinc_tree_set_pass_through(tree:TreeHandle, node:haxe.Int64, through:Bool):Void;

	/** Writes absolute x, y, width, height as four F32s into `out`. **/
	static function blinc_tree_get_bounds(tree:TreeHandle, node:haxe.Int64, out:hl.Bytes):Bool;

	/** Writes padding, border and margin, each top, right, bottom and left, as twelve F32s into `out`. **/
	static function blinc_tree_get_box(tree:TreeHandle, node:haxe.Int64, out:hl.Bytes):Bool;

	/** Whether any of `node`'s box is on screen, inside the root and every box clipping it, scrolled as they are. **/
	static function blinc_tree_in_view(tree:TreeHandle, node:haxe.Int64):Bool;
}
#end
