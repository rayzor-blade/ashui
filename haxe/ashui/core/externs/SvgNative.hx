package ashui.core.externs;

import ashui.core.NativeBytes;

import ashui.core.externs.Handles;

#if ashui_rayzor
/** `SvgNative` over the `blinc_abi` Rayzor plugin's resources. **/
class SvgNative {
	public static inline function blinc_svg_rasterize(markup:NativeBytes, width:Int, height:Int, out:NativeBytes):Bool
		return BlincPlugin.blinc_res_rasterize_svg(markup == null ? "" : ashui.core.Utf8.decode(markup), width, height, (out : haxe.io.Bytes));
}
#elseif ashui_caribou
/** `SvgNative` over the `blinc_abi` Caribou plugin's `Resources`. **/
class SvgNative {
	public static inline function blinc_svg_rasterize(markup:NativeBytes, width:Int, height:Int, out:NativeBytes):Bool
		return blinc_abi.Resources.rasterize_svg(markup == null ? "" : @:privateAccess String.fromUTF8(markup), width, height,
			@:privateAccess new haxe.io.Bytes(out, width * height * 4));
}
#else
/** Turns SVG markup into pixels, in the native library `blinc_abi.hdll`. `ashui.core.render.Images` calls it to fill the image atlas. **/
@:hlNative("blinc_abi")
extern class SvgNative {
	/**
		Rasterizes UTF-8 `markup` into `width` × `height` straight-alpha RGBA
		pixels in `out`, its viewBox fitted and centred. False when it does
		not parse.
	**/
	static function blinc_svg_rasterize(markup:NativeBytes, width:Int, height:Int, out:NativeBytes):Bool;
}
#end
