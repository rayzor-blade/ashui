package ashui.types;

import ashui.core.externs.BlincNative;

/**
	The radii of a box's four corners in pixels, top-left first and
	clockwise. A radius past half the box's shorter side is drawn as that
	half. How each corner curves is its `CornerShape`.
**/
class CornerRadius implements IValue {
	public var ptr(default, null):hl.Abstract<"blinc_value">;
	public final topLeft:Float;
	public final topRight:Float;
	public final bottomRight:Float;
	public final bottomLeft:Float;

	public function new(topLeft:Single, topRight:Single, bottomRight:Single, bottomLeft:Single) {
		this.topLeft = topLeft;
		this.topRight = topRight;
		this.bottomRight = bottomRight;
		this.bottomLeft = bottomLeft;
		this.ptr = BlincNative.blinc_corner_radius(topLeft, topRight, bottomRight, bottomLeft);
	}

	/** `radius` on every corner. **/
	public static inline function all(radius:Single):CornerRadius {
		return new CornerRadius(radius, radius, radius, radius);
	}
}
