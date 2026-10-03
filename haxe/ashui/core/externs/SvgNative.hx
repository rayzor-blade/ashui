package ashui.core.externs;

/** SVG rasterization in `blinc_abi.hdll`. **/
@:hlNative("blinc_abi")
extern class SvgNative {
	/**
		Rasterizes UTF-8 `markup` into `width` × `height` straight-alpha RGBA
		pixels in `out`, its viewBox fitted and centred. False when it does
		not parse.
	**/
	static function blinc_svg_rasterize(markup:hl.Bytes, width:Int, height:Int, out:hl.Bytes):Bool;
}
