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
	public static inline var RECORD_FLOATS = 48;
	public static inline var RECORD_BYTES = RECORD_FLOATS * 4;

	/** Where the primitive type sits in a record, and its values. **/
	public static inline var KIND_FIELD = 44;
	public static inline var PRIM_RECT = 0;
	public static inline var PRIM_SHADOW = 3;

	public var bytes(default, null):haxe.io.Bytes;
	public var count(default, null) = 0;

	var capacity = 0;

	public function new() {}

	/** Fills the list from `tree` under `root`, growing the buffer when it is too small. **/
	public function update(tree:LayoutTree, root:Node):Void {
		var needed = LayoutTreeNative.blinc_tree_display_list(tree.ptr, root.id, bytes == null ? null : bytes.getData(), capacity);
		if (needed > capacity) {
			capacity = needed + (needed >> 1) + 16;
			bytes = haxe.io.Bytes.alloc(capacity * RECORD_BYTES);
			needed = LayoutTreeNative.blinc_tree_display_list(tree.ptr, root.id, bytes.getData(), capacity);
		}
		count = needed;
	}

	/** The primitive type of record `record`. **/
	public inline function kind(record:Int):Int {
		return Std.int(get(record, KIND_FIELD));
	}

	/** Field `field` of record `record`. **/
	public inline function get(record:Int, field:Int):Single {
		return bytes.getFloat((record * RECORD_FLOATS + field) * 4);
	}
}
