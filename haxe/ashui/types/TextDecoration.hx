package ashui.types;

import ashui.core.externs.Handles;
import ashui.core.externs.BlincNative;

/** Which lines a decoration draws, as CSS's `text-decoration-line` names them. **/
enum abstract DecorationLine(Int) to Int {
	var Underline = 1;
	var Overline = 2;
	var LineThrough = 4;
}

/** How a decoration's line is drawn, as CSS's `text-decoration-style`. **/
enum abstract DecorationStyle(Int) to Int {
	var Solid = 0;
	var Double = 1;
	var Dotted = 2;
	var Dashed = 3;
}

/**
	How an element's text, and its descendants', is decorated, as CSS's
	`text-decoration` and its longhands: which lines (`underline`,
	`overline`, `line-through`, several at once), their style, a colour of
	their own or the text's, and a thickness and offset of the font's own
	or given. A descendant's own decoration is drawn beside its
	ancestors', and none undoes them, as CSS's do.
**/
class TextDecoration implements IValue {
	public var ptr(default, null):ValueHandle;

	public function new(lines:Int, ?style:DecorationStyle, ?color:Color, ?thickness:Single, ?offset:Single) {
		// A negative alpha, a NaN thickness and a NaN offset are the font's own, across the ABI.
		ptr = BlincNative.blinc_text_decoration(lines, style == null ? Solid : style, color == null ? 0 : color.rgb, color == null ? -1.0 : color.alpha,
			thickness == null ? Math.NaN : thickness, offset == null ? Math.NaN : offset);
	}
}
