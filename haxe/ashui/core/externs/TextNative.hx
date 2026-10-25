package ashui.core.externs;

import ashui.core.externs.Handles;

#if ashui_caribou
/** `TextNative` over the `blinc_abi` Caribou plugin's `Resources` and `Tree`. **/
class TextNative {
	static inline function text(b:hl.Bytes):String
		return b == null ? "" : @:privateAccess String.fromUTF8(b);

	static inline function wrap(b:hl.Bytes, length:Int):haxe.io.Bytes
		return b == null ? haxe.io.Bytes.alloc(0) : @:privateAccess new haxe.io.Bytes(b, length);

	public static inline function blinc_font_register(bytes:hl.Bytes, len:Int):Int
		return blinc_abi.Resources.register_font(wrap(bytes, len));

	public static inline function blinc_text_atlas_take(color:Int, seen:Int, out:hl.Bytes, capacity:Int, info:hl.Bytes):Int
		return blinc_abi.Resources.text_atlas(color, seen, wrap(out, capacity), wrap(info, 28));

	public static inline function blinc_text_carets(tree:TreeHandle, node:haxe.Int64, text:hl.Bytes, fontSize:Single, wrapWidth:Single, out:hl.Bytes,
			capacity:Int, info:hl.Bytes):Int
		return tree.text_carets(node, TextNative.text(text), fontSize, wrapWidth, wrap(out, capacity * 12), wrap(info, 16));

	public static inline function blinc_text_outline(text:hl.Bytes, font:hl.Bytes, style:hl.Bytes, out:hl.Bytes, capacity:Int, info:hl.Bytes):Int
		return blinc_abi.Resources.text_outline(TextNative.text(text), TextNative.text(font), wrap(style, 24), wrap(out, capacity * 4), wrap(info, 16));
}
#else
/**
	The text engine in the native library, `blinc_abi.hdll`: its glyph
	atlases, the textures it rasterizes glyphs into, and caret positions in
	a laid-out string. `GlyphAtlas` and the text input read these.
**/
@:hlNative("blinc_abi")
extern class TextNative {
	/**
		Adds the faces in `len` bytes of TTF, OpenType, a collection or WOFF2 to
		the installed fonts, found by the family names they carry; how many
		faces it added, 0 when the bytes are none of those. `Fonts` wraps it.
	**/
	static function blinc_font_register(bytes:hl.Bytes, len:Int):Int;

	/**
		The coverage atlas (`color` 0, a byte a pixel) or the colour-glyph
		atlas (`color` 1, RGBA). Each change bumps its revision. When that is
		not `seen`, writes its width, height and revision as three i32s to
		`info` and returns its size in bytes, copying the pixels to `out` when
		they fit in `capacity`. 0 when the caller has seen this revision.
	**/
	static function blinc_text_atlas_take(color:Int, seen:Int, out:hl.Bytes, capacity:Int, info:hl.Bytes):Int;

	/**
		Where a caret can stand in `text`, set in text node `node`'s font at
		`fontSize` (the node's own when 0): for each character boundary, its
		string index, its x and its line, as three F32s in `out`, at most
		`capacity`. With `wrapWidth` above 0, lines wrap at that width, the
		width the node is laid out at. A line break ends a line, and a blank
		line still has a stop. Writes the line height, the line count, and
		the font's ascender and descender (negative) as four F32s to `info`.
		Returns how many stops there are.
	**/
	static function blinc_text_carets(tree:TreeHandle, node:haxe.Int64, text:hl.Bytes, fontSize:Single, wrapWidth:Single, out:hl.Bytes,
		capacity:Int, info:hl.Bytes):Int;

	/**
		`text` in a face of `font` (null for the system's), set as `style`
		says, six F32s: the generic family (0 system, 1 monospace, 2 serif, 3
		sans-serif), weight, italic (0 or 1), size in pixels, letter spacing
		and line height; as path commands of its glyphs' outlines, as F32s: 0
		move (x, y), 1 line (x, y), 2 quadratic (cx, cy, x, y), 3 cubic (c1x,
		c1y, c2x, c2y, x, y), 4 close; the first line's baseline at y 0, y
		down, each line `lineHeight` times the face's below the last. Writes
		the widest line's width, the ascent, the descent below the baseline
		and the face's line height, in pixels, as four F32s to `info`.
		Returns how many F32s there are, copying them to `out` when they fit
		in `capacity`; 0 when no face is found.
	**/
	static function blinc_text_outline(text:hl.Bytes, font:hl.Bytes, style:hl.Bytes, out:hl.Bytes, capacity:Int, info:hl.Bytes):Int;
}
#end
