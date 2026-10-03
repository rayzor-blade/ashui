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
	/** The corner `n` of the record's rounded clip, so a squircle parent clips to its own curve. **/
	public static inline var CLIP_SHAPE_FIELD = 47;
	/** The four corners' `n`, top-left first, the theme's smoothing applied. **/
	public static inline var CORNER_SHAPE_FIELD = 48;
	public static inline var PRIM_RECT = 0;
	public static inline var PRIM_SHADOW = 3;
	/** A glyph of text, sampled from a glyph atlas. **/
	public static inline var PRIM_TEXT = 7;
	/** An image in a node's content box, which the renderer looks up in its image atlas. **/
	public static inline var PRIM_IMAGE = 32;

	public var bytes(default, null):haxe.io.Bytes;
	public var count(default, null) = 0;
	final params = haxe.io.Bytes.alloc(32);

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
		fillParams(scale);
		var needed = LayoutTreeNative.blinc_tree_display_list(tree.ptr, root.id, params.getData(), bytes == null ? null : bytes.getData(), capacity);
		if (needed > capacity) {
			capacity = needed + (needed >> 1) + 16;
			bytes = haxe.io.Bytes.alloc(capacity * RECORD_BYTES);
			needed = LayoutTreeNative.blinc_tree_display_list(tree.ptr, root.id, params.getData(), bytes.getData(), capacity);
		}
		count = needed;
	}

	/**
		What the walk needs from the theme, as eight F32s: `scale`; the
		corner `n` the theme smooths corners to (0 when it does not), the
		radius below which corners stay round, and its full radius, as Blinc's
		paint walk applies the shape tokens; and the theme's primary text
		colour now, mid-transition included, for text that sets none.
	**/
	function fillParams(scale:Float):Void {
		params.setFloat(0, scale);
		var theme = ashui.theme.ThemeState.tryGet();
		if (theme == null) {
			for (i in 1...4)
				params.setFloat(i * 4, i == 1 ? 0 : Math.POSITIVE_INFINITY);
			for (i in 4...8)
				params.setFloat(i * 4, i == 7 ? 1 : 0);
			return;
		}
		var shape = theme.shape();
		params.setFloat(4, shape.isOff() ? 0 : shape.effectiveCornerN());
		params.setFloat(8, shape.smoothingThreshold);
		params.setFloat(12, theme.radii().radiusFull);
		var c = theme.color(TextPrimary);
		params.setFloat(16, c.r);
		params.setFloat(20, c.g);
		params.setFloat(24, c.b);
		params.setFloat(28, Math.max(0, Math.min(1, c.a)));
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
