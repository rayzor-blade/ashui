package ashui.types;

import ashui.core.externs.BlincNative;

/**
	How each corner of a box curves, top-left first, as a number `n`, as
	CSS's `corner-shape: superellipse(n)`. The corner follows the
	superellipse `|x|^k + |y|^k = 1` with `k = 2^|n|`, scaled to its
	`CornerRadius`: 1 is a circular arc, the usual rounded corner; 2 a
	squircle, squarer, blending into the straight sides with no visible
	join; 0 a straight bevel; higher values come closer to a square corner,
	and 100 or more is one. A negative `n` curves the corner inward: -1 is
	a scoop, and -100 or less a square notch.

	Set on a node, it wins over the theme's corner smoothing (see
	`ashui.theme.ShapeTokens`), which turns round corners into squircles;
	`lock` keeps a round shape round too.
**/
class CornerShape implements IValue {
	public var ptr(default, null):hl.Abstract<"blinc_value">;
	public final topLeft:Float;
	public final topRight:Float;
	public final bottomRight:Float;
	public final bottomLeft:Float;
	public final locked:Bool;

	public function new(topLeft:Float, topRight:Float, bottomRight:Float, bottomLeft:Float, locked = false) {
		this.topLeft = topLeft;
		this.topRight = topRight;
		this.bottomRight = bottomRight;
		this.bottomLeft = bottomLeft;
		this.locked = locked;
		ptr = BlincNative.blinc_corner_shape(topLeft, topRight, bottomRight, bottomLeft, locked);
	}

	/** `n` on every corner. **/
	public static inline function all(n:Float):CornerShape
		return new CornerShape(n, n, n, n);

	public static inline function round():CornerShape
		return all(1);

	public static inline function squircle():CornerShape
		return all(2);

	public static inline function bevel():CornerShape
		return all(0);

	public static inline function scoop():CornerShape
		return all(-1);

	public static inline function notch():CornerShape
		return all(-100);

	public static inline function square():CornerShape
		return all(100);

	/** A superellipse of exponent `2^n` on every corner, as CSS `superellipse(n)`. **/
	public static inline function superellipse(n:Float):CornerShape
		return all(n);

	/** This shape, kept whatever the theme. **/
	public function lock():CornerShape {
		return new CornerShape(topLeft, topRight, bottomRight, bottomLeft, true);
	}
}
