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
	/** An image in a node's content box, which the renderer looks up in its image atlas. **/
	public static inline var PRIM_IMAGE = 32;

	public var bytes(default, null):haxe.io.Bytes;
	public var count(default, null) = 0;

	var capacity = 0;

	public function new() {}

	/**
		Fills the list from `tree` under `root`, growing the buffer when it is
		too small. `scale` is the device pixels per layout unit of the target,
		which text is rasterized for.

		Text colour is inherited as in CSS: an element's own colour, from a
		class such as `text-error`, a `color` attribute or a binding, applies
		to it and to everything inside it that sets none, text and the
		`currentColor` of SVG alike. What sets none at all takes the theme's
		primary text colour, or black without a theme. It is resolved while
		the list is built, so content added or recoloured later inherits what
		its ancestors have then.
	**/
	public function update(tree:LayoutTree, root:Node, scale = 1.0):Void {
		var textColor = defaultTextColor();
		var needed = LayoutTreeNative.blinc_tree_display_list(tree.ptr, root.id, scale, textColor, bytes == null ? null : bytes.getData(), capacity);
		if (needed > capacity) {
			capacity = needed + (needed >> 1) + 16;
			bytes = haxe.io.Bytes.alloc(capacity * RECORD_BYTES);
			needed = LayoutTreeNative.blinc_tree_display_list(tree.ptr, root.id, scale, textColor, bytes.getData(), capacity);
		}
		count = needed;
		smoothCorners();
	}

	/** The theme's primary text colour now, mid-transition included, as `0xAARRGGBB`. **/
	static function defaultTextColor():Int {
		var theme = ashui.theme.ThemeState.tryGet();
		if (theme == null)
			return 0xff000000;
		var c = theme.color(TextPrimary);
		return Math.round(Math.max(0, Math.min(1, c.a)) * 255) << 24 | c.rgb();
	}

	/** Gives each record the installed theme's squircle, as Blinc's paint walk does; nothing without a theme. **/
	function smoothCorners():Void {
		var theme = ashui.theme.ThemeState.tryGet();
		if (theme == null)
			return;
		var shape = theme.shape();
		var radiusFull = theme.radii().radiusFull;
		for (r in 0...count) {
			if (kind(r) == PRIM_TEXT || kind(r) == PRIM_IMAGE)
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

	/** Sets field `field` of record `record`, for the renderer filling in what only it knows. **/
	public inline function set(record:Int, field:Int, value:Float):Void {
		bytes.setFloat((record * RECORD_FLOATS + field) * 4, value);
	}

	/** Field `field` of record `record`. **/
	public inline function get(record:Int, field:Int):Single {
		return bytes.getFloat((record * RECORD_FLOATS + field) * 4);
	}
}
