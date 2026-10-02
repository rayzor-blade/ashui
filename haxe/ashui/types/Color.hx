package ashui.types;

import ashui.core.externs.BlincNative;

class Color implements IValue {
	public var ptr(default, null):hl.Abstract<"blinc_value">;

	/** `hex` is `0xRRGGBB`. **/
	public function new(hex:Int, alpha:Single = 1.0) {
		this.ptr = BlincNative.blinc_color_hex(hex, alpha);
	}
}
