package ashui.core.externs;

import ashui.core.NativeBytes;

import ashui.core.externs.Handles;

#if ashui_rayzor
/** `BitmapNative` over the `blinc_abi` Rayzor plugin's `Resources`. **/
class BitmapNative {
	static inline function wrap(b:NativeBytes, length:Int):haxe.io.Bytes
		return b == null ? BlincPlugin.NoBytes.empty : (b : haxe.io.Bytes);

	public static inline function blinc_bitmap_decode(bytes:NativeBytes, len:Int):Int
		return BlincPlugin.blinc_res_decode_bitmap(wrap(bytes, len));

	public static inline function blinc_bitmap_size(slot:Int, height:Bool):Int
		return BlincPlugin.blinc_res_bitmap_size(slot, height);

	public static inline function blinc_bitmap_release(slot:Int):Void
		BlincPlugin.blinc_res_release_bitmap(slot);

	public static inline function blinc_bitmap_resample(slot:Int, width:Int, height:Int, fit:Int, out:NativeBytes):Bool
		return BlincPlugin.blinc_res_resample_bitmap(slot, width, height, fit, wrap(out, width * height * 4));

	public static inline function blinc_bitmap_shrink(slot:Int, maxSide:Int):Bool
		return BlincPlugin.blinc_res_shrink_bitmap(slot, maxSide);
}
#elseif ashui_caribou
/** `BitmapNative` over the `blinc_abi` Caribou plugin's `Resources`. **/
class BitmapNative {
	static inline function wrap(b:NativeBytes, length:Int):haxe.io.Bytes
		return b == null ? haxe.io.Bytes.alloc(0) : @:privateAccess new haxe.io.Bytes(b, length);

	public static inline function blinc_bitmap_decode(bytes:NativeBytes, len:Int):Int
		return blinc_abi.Resources.decode_bitmap(wrap(bytes, len));

	public static inline function blinc_bitmap_size(slot:Int, height:Bool):Int
		return blinc_abi.Resources.bitmap_size(slot, height);

	public static inline function blinc_bitmap_release(slot:Int):Void
		blinc_abi.Resources.release_bitmap(slot);

	public static inline function blinc_bitmap_resample(slot:Int, width:Int, height:Int, fit:Int, out:NativeBytes):Bool
		return blinc_abi.Resources.resample_bitmap(slot, width, height, fit, wrap(out, width * height * 4));

	public static inline function blinc_bitmap_shrink(slot:Int, maxSide:Int):Bool
		return blinc_abi.Resources.shrink_bitmap(slot, maxSide);
}
#else
/**
	Decodes and resamples raster images in the native library,
	`blinc_abi.hdll`. A decoded image is kept under a numbered slot until it
	is released. `ashui.types.Bitmap` wraps these calls; app code uses that.
	Implemented in `blinc_abi::bitmap`.
**/
@:hlNative("blinc_abi")
extern class BitmapNative {
	/** Decodes `len` bytes of PNG or JPEG; its slot, or -1 when they are not one. **/
	static function blinc_bitmap_decode(bytes:NativeBytes, len:Int):Int;

	/** The width, or with `height` the height, of the bitmap in `slot`. **/
	static function blinc_bitmap_size(slot:Int, height:Bool):Int;

	/** Frees the bitmap in `slot`; the slot must not be drawn after. **/
	static function blinc_bitmap_release(slot:Int):Void;

	/** Writes the bitmap fitted by `fit` into `out`, `width` × `height` straight RGBA pixels. **/
	static function blinc_bitmap_resample(slot:Int, width:Int, height:Int, fit:Int, out:NativeBytes):Bool;

	/** Shrinks the bitmap so neither side is over `maxSide`, keeping its shape, each side a multiple of 4; false when it was small enough. **/
	static function blinc_bitmap_shrink(slot:Int, maxSide:Int):Bool;
}
#end
