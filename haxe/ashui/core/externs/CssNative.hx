package ashui.core.externs;

import ashui.core.externs.Handles;

#if ashui_caribou
/** `CssNative` over the `blinc_abi` Caribou plugin's `Css` and `Sheet`. **/
class CssNative {
	static inline function text(b:hl.Bytes):String
		return b == null ? "" : @:privateAccess String.fromUTF8(b);

	static inline function bytes(s:String):hl.Bytes
		return s == null ? null : @:privateAccess s.toUtf8();

	static inline function wrap(b:hl.Bytes, length:Int):haxe.io.Bytes
		return b == null ? haxe.io.Bytes.alloc(0) : @:privateAccess new haxe.io.Bytes(b, length);

	/** A result the engine reports as empty text where HashLink's is null. **/
	static inline function orNull(s:String):hl.Bytes
		return s == null || s == "" ? null : bytes(s);

	public static inline function blinc_css_new():CssHandle
		return new blinc_abi.Css();

	public static function blinc_css_add(css:CssHandle, source:hl.Bytes, file:hl.Bytes, at:Int, id:hl.Ref<Int>):hl.Bytes {
		id.set(css.add(text(source), text(file), at));
		return bytes(css.diagnostics());
	}

	public static inline function blinc_css_parse(source:hl.Bytes, file:hl.Bytes):SheetHandle
		return blinc_abi.Sheet.parse(text(source), text(file));

	public static inline function blinc_css_decode(data:hl.Bytes, length:Int):SheetHandle
		return blinc_abi.Sheet.decode(wrap(data, length));

	public static inline function blinc_css_sheet_diagnostics(sheet:SheetHandle):hl.Bytes
		return bytes(sheet.diagnostics());

	public static inline function blinc_css_sheet_imports(sheet:SheetHandle):hl.Bytes
		return bytes(sheet.imports());

	public static inline function blinc_css_sheet_declared(sheet:SheetHandle):hl.Bytes
		return bytes(sheet.declared());

	public static inline function blinc_css_add_parsed(css:CssHandle, sheet:SheetHandle, at:Int):Int
		return css.add_parsed(sheet, at);

	public static inline function blinc_css_keyframes(css:CssHandle, name:hl.Bytes):hl.Bytes
		return orNull(css.keyframes(text(name)));

	public static inline function blinc_css_root_variable(css:CssHandle, name:hl.Bytes):hl.Bytes
		return orNull(css.root_variable(text(name)));

	public static inline function blinc_css_add_compiled(css:CssHandle, data:hl.Bytes, length:Int, at:Int):Int
		return css.add_compiled(wrap(data, length), at);

	public static inline function blinc_css_remove(css:CssHandle, id:Int):Int
		return css.remove(id);

	public static inline function blinc_css_set_theme(css:CssHandle, vars:hl.Bytes):Void
		css.set_theme(text(vars));

	public static inline function blinc_css_set_environment(css:CssHandle, width:Float, height:Float, dark:Int, rootFontSize:Float):Void
		css.set_environment(width, height, dark != 0, rootFontSize);

	public static inline function blinc_css_set_element(css:CssHandle, node:haxe.Int64, desc:hl.Bytes):Void
		css.set_element(node, text(desc));

	public static inline function blinc_css_state_bit(name:hl.Bytes):Int
		return blinc_abi.Css.state_bit(text(name));

	public static inline function blinc_css_set_states(css:CssHandle, node:haxe.Int64, mask:Int):Void
		css.set_states(node, mask);

	public static inline function blinc_css_moved(css:CssHandle, node:haxe.Int64):Void
		css.moved(node);

	public static inline function blinc_css_children_changed(css:CssHandle, parent:haxe.Int64):Void
		css.children_changed(parent);

	public static inline function blinc_css_forget(css:CssHandle, node:haxe.Int64):Void
		css.forget(node);

	public static inline function blinc_css_restyle(css:CssHandle, tree:TreeHandle, root:haxe.Int64):Int
		return css.restyle(tree, root);

	public static inline function blinc_css_take_changed(css:CssHandle, out:hl.Bytes, capacity:Int):Int
		return css.take_changed(wrap(out, capacity * 8));

	public static inline function blinc_css_take_watched(css:CssHandle, nodes:hl.Bytes, bits:hl.Bytes, capacity:Int):Int
		return css.take_watched(wrap(nodes, capacity * 8), wrap(bits, capacity * 4));

	public static inline function blinc_css_select(css:CssHandle, tree:TreeHandle, root:haxe.Int64, selectors:hl.Bytes, out:hl.Bytes, capacity:Int):Int
		return css.select(tree, root, text(selectors), wrap(out, capacity * 8));

	public static inline function blinc_css_style(css:CssHandle, node:haxe.Int64):hl.Bytes
		return bytes(css.style(node));

	public static inline function blinc_css_explain(css:CssHandle, tree:TreeHandle, node:haxe.Int64):hl.Bytes
		return bytes(css.explain(tree, node));
}
#else
/**
	The native CSS engine of `blinc_abi.hdll`: parsing, selector matching
	and the cascade, over the layout tree. Each UI context owns an engine.
	`ashui.css.Css` drives it; app code uses that.

	Strings cross as UTF-8 (`toUtf8`, `String.fromUTF8`). Lists cross as one
	string: records split by U+0001, a name and its value by U+0002, and the
	items of one record by U+0003. Flags cross as `Int`.
**/
@:hlNative("blinc_abi")
extern class CssNative {
	static function blinc_css_new():CssHandle;

	/** Parses `source` and adds it at `at`; writes its id to `id`, -1 if none, and returns its diagnostics, each `severity, line, column, file, message`. **/
	static function blinc_css_add(css:CssHandle, source:hl.Bytes, file:hl.Bytes, at:Int, id:hl.Ref<Int>):hl.Bytes;

	/** CSS text parsed, as a sheet to add; `file` names it and is where its imports are read from. **/
	static function blinc_css_parse(source:hl.Bytes, file:hl.Bytes):SheetHandle;

	/** A compiled sheet decoded, as a sheet to add; null for bytes that do not decode. **/
	static function blinc_css_decode(bytes:hl.Bytes, length:Int):SheetHandle;

	/** A parsed sheet's diagnostics, as `blinc_css_add` returns them. **/
	static function blinc_css_sheet_diagnostics(sheet:SheetHandle):hl.Bytes;

	/** The files a parsed sheet imported, one per record. **/
	static function blinc_css_sheet_imports(sheet:SheetHandle):hl.Bytes;

	/** Every declaration of a parsed sheet's rules: name, line and column per record. **/
	static function blinc_css_sheet_declared(sheet:SheetHandle):hl.Bytes;

	/** Adds a parsed sheet at `at`, which stays the caller's; its id. **/
	static function blinc_css_add_parsed(css:CssHandle, sheet:SheetHandle, at:Int):Int;

	/** The `@keyframes` named `name`: a record per frame, offsets split by spaces, then its declarations as items of name, U+0004, value; null for none. **/
	static function blinc_css_keyframes(css:CssHandle, name:hl.Bytes):hl.Bytes;

	/** `:root`'s custom property `name`, no `--`; null when no sheet declares it. **/
	static function blinc_css_root_variable(css:CssHandle, name:hl.Bytes):hl.Bytes;

	/** Adds a compiled sheet at `at`; its id, or -1 for bytes that do not decode. **/
	static function blinc_css_add_compiled(css:CssHandle, bytes:hl.Bytes, length:Int, at:Int):Int;

	static function blinc_css_remove(css:CssHandle, id:Int):Int;

	/** The theme's variables, names without `--`, as name-value records. **/
	static function blinc_css_set_theme(css:CssHandle, vars:hl.Bytes):Void;

	static function blinc_css_set_environment(css:CssHandle, width:Float, height:Float, dark:Int, rootFontSize:Float):Void;

	/** Six records: types (own first) and classes split by spaces, the id, attributes and inline declarations as name-value items, `1` when a layout made it. **/
	static function blinc_css_set_element(css:CssHandle, node:haxe.Int64, desc:hl.Bytes):Void;

	/** State `name`'s bit in `set_states`'s mask; 0 for one the engine does not know. **/
	static function blinc_css_state_bit(name:hl.Bytes):Int;

	static function blinc_css_set_states(css:CssHandle, node:haxe.Int64, mask:Int):Void;
	static function blinc_css_moved(css:CssHandle, node:haxe.Int64):Void;
	static function blinc_css_children_changed(css:CssHandle, parent:haxe.Int64):Void;
	static function blinc_css_forget(css:CssHandle, node:haxe.Int64):Void;

	/** Restyles what changed under `root`; how many nodes' styles changed. **/
	static function blinc_css_restyle(css:CssHandle, tree:TreeHandle, root:haxe.Int64):Int;

	/** The nodes whose styles changed, parents first, as 64-bit ids in `out`; how many it wrote. **/
	static function blinc_css_take_changed(css:CssHandle, out:hl.Bytes, capacity:Int):Int;

	/** States selectors began to test: node ids in `nodes`, state bits in `bits`; how many. **/
	static function blinc_css_take_watched(css:CssHandle, nodes:hl.Bytes, bits:hl.Bytes, capacity:Int):Int;

	/** The elements under `root` that the selectors match, in document order, as ids in `out`; how many match, or -1 for selectors that do not read. **/
	static function blinc_css_select(css:CssHandle, tree:TreeHandle, root:haxe.Int64, selectors:hl.Bytes, out:hl.Bytes,
		capacity:Int):Int;

	/** Three records: resolved declarations and values as name-value items, then the font size in pixels. **/
	static function blinc_css_style(css:CssHandle, node:haxe.Int64):hl.Bytes;

	/** Every declaration that applies to `node`, in cascade order: records of name, value, sheet id (-1 its own), selector, line, important and wins. **/
	static function blinc_css_explain(css:CssHandle, tree:TreeHandle, node:haxe.Int64):hl.Bytes;
}
#end
