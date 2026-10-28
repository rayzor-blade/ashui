package ashui.types;

import ashui.core.externs.Handles;
import ashui.core.externs.BlincNative;

/**
	Defines each corner's shape, starting at the top left.
	Values follow CSS `corner-shape: superellipse(n)`. The curve is
	`|x|^k + |y|^k = 1`, with `k = 2^|n|`, scaled by `CornerRadius`.

	- `1`: a circular rounded corner.
	- `2`: a squircle that blends smoothly into straight sides.
	- `0`: a straight bevel.
	- Larger values approach a square corner; `100` or more is square.
	- Negative values curve inward: `-1` is a scoop; `-100` or less is a notch.

	Explicit corner shapes override theme smoothing. Set `lock` to prevent
	an explicitly round shape from being smoothed into a squircle.
	See `ashui.theme.ShapeTokens`.
**/
class CornerShape implements IValue {
	public var ptr(default, null):ValueHandle;
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
