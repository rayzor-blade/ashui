package ashui.core.externs;

/** Raster images in `blinc_abi.hdll`: see `blinc_abi::bitmap`. **/
@:hlNative("blinc_abi")
extern class BitmapNative {
	/** Decodes `len` bytes of PNG or JPEG; its slot, or -1 when they are not one. **/
	static function blinc_bitmap_decode(bytes:hl.Bytes, len:Int):Int;

	/** The width, or with `height` the height, of the bitmap in `slot`. **/
	static function blinc_bitmap_size(slot:Int, height:Bool):Int;

	static function blinc_bitmap_release(slot:Int):Void;

	/** Writes the bitmap fitted by `fit` into `out`, `width` × `height` straight RGBA pixels. **/
	static function blinc_bitmap_resample(slot:Int, width:Int, height:Int, fit:Int, out:hl.Bytes):Bool;
}
