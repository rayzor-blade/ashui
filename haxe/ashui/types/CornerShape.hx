package ashui.types;

import ashui.core.externs.BlincNative;

/**
	How each corner curves, as a superellipse `n`, top-left first: 1 round,
	2 squircle, 0 bevel, -1 scoop, 100 square, -100 notch. Set on a node,
	it wins over the theme's squircle; `lock` keeps a round shape round too.
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
