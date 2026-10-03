package ashui.layout;

import ashui.core.externs.LayoutTreeNative;

/**
	The primitives to draw under a node after layout, packed by `blinc_abi`
	for a GPU vertex buffer: `count` records of `RECORD_FLOATS` F32s in
	`bytes`, in paint order. A record is a subset of Blinc's `GpuPrimitive`,
	documented in blinc_abi/src/display_list.rs. `bytes` can be uploaded as
	it is.
**/
class DisplayList {
	public static inline var RECORD_FLOATS = 64;
	public static inline var RECORD_BYTES = RECORD_FLOATS * 4;

	/** Where the primitive type sits in a record, and its values. **/
	public static inline var KIND_FIELD = 44;
	/** 1 when the node keeps its corner shape whatever the theme. **/
	public static inline var SHAPE_LOCKED_FIELD = 47;
	/** The four corners' `n`, top-left first. **/
	public static inline var CORNER_SHAPE_FIELD = 48;
	public static inline var PRIM_RECT = 0;
	public static inline var PRIM_SHADOW = 3;
	/** A glyph of text, sampled from a glyph atlas. **/
	public static inline var PRIM_TEXT = 7;

	public var bytes(default, null):haxe.io.Bytes;
	public var count(default, null) = 0;

	var capacity = 0;

	public function new() {}

	/**
		Fills the list from `tree` under `root`, growing the buffer when it is
		too small. `scale` is the device pixels per layout unit of the target,
		which text is rasterized for.
	**/
	public function update(tree:LayoutTree, root:Node, scale = 1.0):Void {
		var needed = LayoutTreeNative.blinc_tree_display_list(tree.ptr, root.id, scale, bytes == null ? null : bytes.getData(), capacity);
		if (needed > capacity) {
			capacity = needed + (needed >> 1) + 16;
			bytes = haxe.io.Bytes.alloc(capacity * RECORD_BYTES);
			needed = LayoutTreeNative.blinc_tree_display_list(tree.ptr, root.id, scale, bytes.getData(), capacity);
		}
		count = needed;
		smoothCorners();
	}

	/** Gives each record the installed theme's squircle, as Blinc's paint walk does; nothing without a theme. **/
	function smoothCorners():Void {
		var theme = ashui.theme.ThemeState.tryGet();
		if (theme == null)
			return;
		var shape = theme.shape();
		var radiusFull = theme.radii().radiusFull;
		for (r in 0...count) {
			if (kind(r) == PRIM_TEXT)
				continue;
			var explicit:Array<Float> = [for (c in 0...4) get(r, CORNER_SHAPE_FIELD + c)];
			var radii:Array<Float> = [for (c in 4...8) get(r, c)];
			var resolved = ashui.core.render.CornerShapes.resolve(explicit, radii, get(r, 2), get(r, 3), shape,
				radiusFull, get(r, SHAPE_LOCKED_FIELD) == 1);
			for (c in 0...4)
				set(r, CORNER_SHAPE_FIELD + c, resolved[c]);
		}
	}

	/** The primitive type of record `record`. **/
	public inline function kind(record:Int):Int {
		return Std.int(get(record, KIND_FIELD));
	}

	inline function set(record:Int, field:Int, value:Float):Void {
		bytes.setFloat((record * RECORD_FLOATS + field) * 4, value);
	}

	/** Field `field` of record `record`. **/
	public inline function get(record:Int, field:Int):Single {
		return bytes.getFloat((record * RECORD_FLOATS + field) * 4);
	}
}
