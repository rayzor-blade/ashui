package ashui.types;

import ashui.core.externs.BlincNative;

/**
	A box shadow: one or more layers, each an offset, a blur, a spread and a
	colour. Layers are drawn last first, so the first is on top.
**/
class Shadow implements IValue {
	public var ptr(default, null):hl.Abstract<"blinc_value">;
	/** Each layer: offset x, offset y, blur, spread, colour, alpha. **/
	public final layers:Array<Array<Float>> = [];

	public function new(offsetX:Single, offsetY:Single, blur:Single, colorHex:Int, colorAlpha:Single = 1.0, spread:Single = 0) {
		this.ptr = BlincNative.blinc_shadow(offsetX, offsetY, blur, spread, colorHex, colorAlpha);
		layers.push([offsetX, offsetY, blur, spread, colorHex, colorAlpha]);
	}

	/** Adds a layer under the ones before it; returns this shadow. Set it on a node after adding every layer. **/
	public function and(offsetX:Single, offsetY:Single, blur:Single, colorHex:Int, colorAlpha:Single = 1.0, spread:Single = 0):Shadow {
		BlincNative.blinc_shadow_push(ptr, offsetX, offsetY, blur, spread, colorHex, colorAlpha);
		layers.push([offsetX, offsetY, blur, spread, colorHex, colorAlpha]);
		return this;
	}
}
