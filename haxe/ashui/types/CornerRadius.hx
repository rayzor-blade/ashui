package ashui.types;

import ashui.core.externs.BlincNative;

class CornerRadius implements IValue {
	public var ptr(default, null):hl.Abstract<"blinc_value">;

	public function new(topLeft:Single, topRight:Single, bottomRight:Single, bottomLeft:Single) {
		this.ptr = BlincNative.blinc_corner_radius(topLeft, topRight, bottomRight, bottomLeft);
	}

	public static inline function all(radius:Single):CornerRadius {
		return new CornerRadius(radius, radius, radius, radius);
	}
}
