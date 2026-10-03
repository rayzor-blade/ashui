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
}
