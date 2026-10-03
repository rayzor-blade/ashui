package ashui.types;

import ashui.core.externs.BlincNative;

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

	public static inline function all(radius:Single):CornerRadius {
		return new CornerRadius(radius, radius, radius, radius);
	}
}
