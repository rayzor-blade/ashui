package ashui.types;

import ashui.core.externs.Handles;
import ashui.core.externs.BlincNative;

/** A colour as a style value: `0xRRGGBB` and an alpha from 0 to 1, in sRGB. **/
class Color implements IValue {
	public var ptr(default, null):ValueHandle;

	/**
		Frees the native copy, for good; a value set on a node after that clears the property, like null. Safe to call
		twice. Rayzor has no collector to do this; on HashLink it is optional.
	**/
	public function dispose():Void {
		if (ptr == null)
			return;
		BlincNative.blinc_value_release(ptr);
		ptr = null;
	}
	public final rgb:Int;
	public final alpha:Float;

	/** `hex` is `0xRRGGBB`. **/
	public function new(hex:Int, alpha:Single = 1.0) {
		this.rgb = hex;
		this.alpha = alpha;
		this.ptr = BlincNative.blinc_color_hex(hex, alpha);
	}
}
