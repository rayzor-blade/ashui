package ashui.core.externs;

/** Turns SVG markup into pixels, in the native library `blinc_abi.hdll`. `ashui.core.render.Images` calls it to fill the image atlas. **/
@:hlNative("blinc_abi")
extern class SvgNative {
	/**
		Rasterizes UTF-8 `markup` into `width` × `height` straight-alpha RGBA
		pixels in `out`, its viewBox fitted and centred. False when it does
		not parse.
	**/
	static function blinc_svg_rasterize(markup:hl.Bytes, width:Int, height:Int, out:hl.Bytes):Bool;
}
