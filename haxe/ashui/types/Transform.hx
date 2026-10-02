package ashui.types;

import ashui.core.externs.BlincNative;

class Transform implements IValue {
	public var ptr(default, null):hl.Abstract<"blinc_value">;

	public function new(ptr:hl.Abstract<"blinc_value">) {
		this.ptr = ptr;
	}

	public static inline function identity():Transform {
		return new Transform(BlincNative.blinc_transform_identity());
	}

	public static inline function translation(x:Single, y:Single):Transform {
		return new Transform(BlincNative.blinc_transform_translate(x, y));
	}
}
