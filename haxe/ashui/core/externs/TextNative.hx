package ashui.core.externs;

/** The glyph atlases of the text engine in `blinc_abi.hdll`. **/
@:hlNative("blinc_abi")
extern class TextNative {
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
		line still has a stop. Writes the line height and the line count as
		two F32s to `info`. Returns how many stops there are.
	**/
	static function blinc_text_carets(tree:hl.Abstract<"blinc_tree">, node:haxe.Int64, text:hl.Bytes, fontSize:Single, wrapWidth:Single,
		out:hl.Bytes, capacity:Int, info:hl.Bytes):Int;
}
