package ashui.types;

import ashui.core.externs.BlincNative;

/**
	A 2D transform of an element, applied about its centre after its
	ancestors' transforms, as CSS's `transform` is. It keeps its parts —
	move, turn, slant and stretch — and composes them in Tailwind's order:
	translate, rotate, skew x, skew y, scale. A transition between two
	transforms moves each part, so a turn turns rather than shrinking.
**/
class Transform implements IValue {
	public var ptr(default, null):hl.Abstract<"blinc_value">;

	/** Pixels. **/
	public final translateX:Float;
	public final translateY:Float;

	/** Degrees, clockwise. **/
	public final rotate:Float;

	public final scaleX:Float;
	public final scaleY:Float;

	/** Degrees. **/
	public final skewX:Float;
	public final skewY:Float;

	public function new(translateX = 0.0, translateY = 0.0, rotate = 0.0, scaleX = 1.0, scaleY = 1.0, skewX = 0.0, skewY = 0.0) {
		this.translateX = translateX;
		this.translateY = translateY;
		this.rotate = rotate;
		this.scaleX = scaleX;
		this.scaleY = scaleY;
		this.skewX = skewX;
		this.skewY = skewY;
		var m = matrix();
		ptr = BlincNative.blinc_transform_affine(m[0], m[1], m[2], m[3], m[4], m[5]);
	}

	public static inline function identity():Transform
		return new Transform();

	public static inline function translation(x:Float, y:Float):Transform
		return new Transform(x, y);

	public static inline function rotation(degrees:Float):Transform
		return new Transform(0, 0, degrees);

	public static inline function scaling(x:Float, ?y:Float):Transform
		return new Transform(0, 0, 0, x, y != null ? y : x);

	/**
		The matrix `[a, b, c, d, tx, ty]`: a point `(x, y)` goes to
		`(a·x + c·y + tx, b·x + d·y + ty)`.
	**/
	public function matrix():Array<Float> {
		var r = rotate * Math.PI / 180;
		var cos = Math.cos(r), sin = Math.sin(r);
		var kx = Math.tan(skewX * Math.PI / 180), ky = Math.tan(skewY * Math.PI / 180);
		// Rotation, then the skews: [cos -sin; sin cos] · [1 kx; 0 1] · [1 0; ky 1].
		var a = cos - sin * ky, c = cos * kx - sin;
		var b = sin + cos * ky, d = sin * kx + cos;
		// Then the scale on the right, and the move on top.
		return [a * scaleX, b * scaleX, c * scaleY, d * scaleY, translateX, translateY];
	}

	/** Each part from `from` to `to` by `t`. **/
	public static function lerp(from:Transform, to:Transform, t:Float):Transform {
		inline function mix(a:Float, b:Float)
			return a + (b - a) * t;
		return new Transform(mix(from.translateX, to.translateX), mix(from.translateY, to.translateY), mix(from.rotate, to.rotate),
			mix(from.scaleX, to.scaleX), mix(from.scaleY, to.scaleY), mix(from.skewX, to.skewX), mix(from.skewY, to.skewY));
	}
}
