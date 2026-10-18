package dashboard;

import ashui.draw.DrawContext;
import ashui.draw.GlyphOutlines.TextAlignment;
import ashui.draw.GlyphOutlines.TextBaseline;
import ashui.theme.ThemeState;
import ashui.types.Brush;

/**
	The colours a canvas draws in: the theme's own, read as the canvas draws, which follows the colour scheme and the
	moment of its change, and the few colours that mean the same in both. A canvas calls `follow` first, so it is drawn
	again when the scheme turns.
**/
class Ink {
	public static inline var AMBER = 0xf59e0b;
	public static inline var GREEN = 0x22c55e;
	public static inline var CYAN = 0x22d3ee;
	public static inline var VIOLET = 0xa78bfa;

	/** Subscribes the canvas drawing to the theme; call it at the top of a draw. **/
	public static inline function follow():Void
		ThemeState.get().revision.get();

	public static inline function ink():Int
		return ThemeState.get().color(TextPrimary).rgb();

	/** Secondary text and the faint marks of a gauge: the theme's tertiary, lifted in the dark scheme, whose page is a mid silver. **/
	public static inline function muted():Int
		return light() ? ThemeState.get().color(TextTertiary).rgb() : 0xd2d7e0;

	public static inline function primary():Int
		return ThemeState.get().color(Primary).rgb();

	public static inline function light():Bool
		return ThemeState.get().scheme() == Light;

	/** `s` at (`x`, `y`), its middle on the point unless `align` says otherwise. **/
	public static function text(ctx:DrawContext, s:String, x:Float, y:Float, size:Float, weight:Int, color:Int, alpha = 1.0, ?align:TextAlignment):Void
		ctx.text(s, x, y, Brush.solid(color, alpha), {size: size, weight: weight, align: align == null ? TextAlignment.Middle : align, baseline: TextBaseline.Middle});
}
