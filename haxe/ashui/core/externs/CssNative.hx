package ashui.core.externs;

/**
	The native CSS engine of `blinc_abi.hdll`: parsing, selector matching
	and the cascade, over the layout tree. One engine serves the process.
	`ashui.css.Css` drives it; app code uses that.

	Strings cross as UTF-8 (`toUtf8`, `String.fromUTF8`). Lists cross as one
	string: records split by U+0001, a name and its value by U+0002, and the
	items of one record by U+0003. Flags cross as `Int`.
**/
@:hlNative("blinc_abi")
extern class CssNative {
	static function blinc_css_new():hl.Abstract<"blinc_css">;

	/** Parses `source` and adds it at `at`; writes its id to `id`, -1 if none, and returns its diagnostics, each `severity, line, column, file, message`. **/
	static function blinc_css_add(css:hl.Abstract<"blinc_css">, source:hl.Bytes, file:hl.Bytes, at:Int, id:hl.Ref<Int>):hl.Bytes;

	/** Adds a compiled sheet at `at`; its id, or -1 for bytes that do not decode. **/
	static function blinc_css_add_compiled(css:hl.Abstract<"blinc_css">, bytes:hl.Bytes, length:Int, at:Int):Int;

	static function blinc_css_remove(css:hl.Abstract<"blinc_css">, id:Int):Int;

	/** The theme's variables, names without `--`, as name-value records. **/
	static function blinc_css_set_theme(css:hl.Abstract<"blinc_css">, vars:hl.Bytes):Void;

	static function blinc_css_set_environment(css:hl.Abstract<"blinc_css">, width:Float, height:Float, dark:Int, rootFontSize:Float):Void;

	/** Six records: types (own first) and classes split by spaces, the id, attributes and inline declarations as name-value items, `1` when a layout made it. **/
	static function blinc_css_set_element(css:hl.Abstract<"blinc_css">, node:haxe.Int64, desc:hl.Bytes):Void;

	/** State `name`'s bit in `set_states`'s mask; 0 for one the engine does not know. **/
	static function blinc_css_state_bit(name:hl.Bytes):Int;

	static function blinc_css_set_states(css:hl.Abstract<"blinc_css">, node:haxe.Int64, mask:Int):Void;
	static function blinc_css_moved(css:hl.Abstract<"blinc_css">, node:haxe.Int64):Void;
	static function blinc_css_children_changed(css:hl.Abstract<"blinc_css">, parent:haxe.Int64):Void;
	static function blinc_css_forget(css:hl.Abstract<"blinc_css">, node:haxe.Int64):Void;

	/** Restyles what changed under `root`; how many nodes' styles changed. **/
	static function blinc_css_restyle(css:hl.Abstract<"blinc_css">, tree:hl.Abstract<"blinc_tree">, root:haxe.Int64):Int;

	/** The nodes whose styles changed, parents first, as 64-bit ids in `out`; how many it wrote. **/
	static function blinc_css_take_changed(css:hl.Abstract<"blinc_css">, out:hl.Bytes, capacity:Int):Int;

	/** States selectors began to test: node ids in `nodes`, state bits in `bits`; how many. **/
	static function blinc_css_take_watched(css:hl.Abstract<"blinc_css">, nodes:hl.Bytes, bits:hl.Bytes, capacity:Int):Int;

	/** Three records: resolved declarations and values as name-value items, then the font size in pixels. **/
	static function blinc_css_style(css:hl.Abstract<"blinc_css">, node:haxe.Int64):hl.Bytes;
}
