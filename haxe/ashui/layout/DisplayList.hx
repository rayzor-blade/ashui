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
	public static inline var RECORD_FLOATS = 100;
	public static inline var RECORD_BYTES = RECORD_FLOATS * 4;
	public static inline var RECORD_ROWS = RecordLayout.RECORD_ROWS;
	public static inline var ROW_TEXELS = RecordLayout.ROW_TEXELS;
	public static inline var RECORDS_PER_ROW = RecordLayout.RECORDS_PER_ROW;

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
	/** The records after it, to its `PRIM_LAYER`, draw into a layer of their own. **/
	public static inline var PRIM_LAYER_BEGIN = 40;
	/** Composites the layer begun last over its bounds, faded by its colour's alpha. **/
	public static inline var PRIM_LAYER = 41;
	/** What is drawn behind its box, blurred and colour-filtered, drawn back over the box before the element. **/
	public static inline var PRIM_BACKDROP = 42;

	public var bytes(default, null):haxe.io.Bytes;
	public var count(default, null) = 0;

	/** Records' room the list takes in `bytes`: `count` records, then the points of polygon clips. **/
	public var stored(default, null) = 0;

	/** Corner smoothing to draw with instead of the installed theme's, with its full radius; null for the theme's. **/
	public var shapes:Null<{tokens:ashui.theme.ShapeTokens, radiusFull:Float}> = null;

	/** Eight F32s for the walk, and a ninth it writes back: how many records to draw. **/
	final params = haxe.io.Bytes.alloc(36);

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
			// Whole rows of the records texture, so they upload as they are.
			capacity = Math.ceil((needed + (needed >> 1) + 16) / RECORDS_PER_ROW) * RECORDS_PER_ROW;
			bytes = haxe.io.Bytes.alloc(capacity * RECORD_BYTES);
			needed = LayoutTreeNative.blinc_tree_display_list(tree.ptr, root.id, params.getData(), bytes.getData(), capacity);
		}
		stored = needed;
		count = Std.int(params.getFloat(32));
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
		var shape = shapes != null ? shapes.tokens : theme != null ? theme.shape() : null;
		if (shape == null || shape.isOff()) {
			params.setFloat(4, 0);
			params.setFloat(8, Math.POSITIVE_INFINITY);
			params.setFloat(12, Math.POSITIVE_INFINITY);
		} else {
			params.setFloat(4, shape.effectiveCornerN());
			params.setFloat(8, shape.smoothingThreshold);
			params.setFloat(12, shapes != null ? shapes.radiusFull : theme.radii().radiusFull);
		}
		var c:Null<ashui.theme.Rgba> = theme != null ? theme.color(TextPrimary) : null;
		params.setFloat(16, c != null ? c.r : 0);
		params.setFloat(20, c != null ? c.g : 0);
		params.setFloat(24, c != null ? c.b : 0);
		params.setFloat(28, c != null ? Math.max(0, Math.min(1, c.a)) : 1);
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
