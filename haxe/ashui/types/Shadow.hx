package ashui.types;

import ashui.core.externs.BlincNative;

class Shadow implements IValue {
	public var ptr(default, null):hl.Abstract<"blinc_value">;

	public function new(offsetX:Single, offsetY:Single, blur:Single, colorHex:Int, colorAlpha:Single = 1.0) {
		this.ptr = BlincNative.blinc_shadow(offsetX, offsetY, blur, colorHex, colorAlpha);
	}
}
