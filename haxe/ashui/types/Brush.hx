package ashui.types;

import ashui.core.Utf8;
import ashui.core.externs.BlincNative;

/**
	How an image fills a box of another shape, as CSS's `object-fit`:
	`Cover` fills the box and crops the image, `Contain` shows all of it
	inside the box, `Fill` stretches it to the box, `Tile` repeats it.
**/
enum abstract ImageFit(Int) from Int to Int {
	var Cover = 0;
	var Contain = 1;
	var Fill = 2;
	var Tile = 3;
}

/**
	What fills a box, as a node's `Prop.Background`: a solid colour, a
	gradient, an image, or what is behind the box blurred.
**/
class Brush implements IValue {
	public var ptr(default, null):hl.Abstract<"blinc_value">;

	/** A solid brush's colour, `0xRRGGBB`, and alpha; -1 for any other brush. **/
	public var solidRgb(default, null) = -1;
	public var solidAlpha(default, null) = 1.0;

	private function new(ptr:hl.Abstract<"blinc_value">) {
		this.ptr = ptr;
	}

	/** `hex`, `0xRRGGBB`, at `alpha`. **/
	public static function solid(hex:Int, alpha:Single = 1.0):Brush {
		var brush = new Brush(BlincNative.blinc_brush_solid(hex, alpha));
		brush.solidRgb = hex & 0xFFFFFF;
		brush.solidAlpha = alpha;
		return brush;
	}

	/**
		Frosted glass, as iOS and macOS draw it: what is behind the box
		blurred by `blur` and tinted with `tintHex` at `tintAlpha`. `simple`
		is the plain frosting, without refraction, highlights or a bevel at
		the edge.
	**/
	public static inline function glass(blur:Single, tintHex:Int, tintAlpha:Single = 0.1, simple:Bool = false):Brush {
		return new Brush(BlincNative.blinc_brush_glass(blur, tintHex, tintAlpha, simple ? 1 : 0));
	}

	/** What is behind the box blurred by `radius`, untinted. **/
	public static inline function blur(radius:Single):Brush {
		return new Brush(BlincNative.blinc_brush_blur(radius));
	}

	/** The image at `url` filling the box, fitted by `fit`. **/
	public static inline function image(url:String, fit:ImageFit = Cover):Brush {
		return new Brush(BlincNative.blinc_brush_image(Utf8.encode(url), fit));
	}

	/** `bitmap` filling the box, fitted by `fit`, under its border and clipped to its corners, as CSS's `background-image`. **/
	public static function bitmap(bitmap:Bitmap, fit:ImageFit = Cover):Brush {
		return new Brush(BlincNative.blinc_brush_image(Utf8.encode("ashui:bitmap:" + bitmap.slotFor(fit)), fit));
	}

	/**
		A linear gradient from `(x1, y1)` to `(x2, y2)` with no stops yet; add
		them with `stop`, in order. With `boundingBox` the points are fractions
		of the box it fills, else pixels from the box's corner.
	**/
	public static function linear(x1:Single, y1:Single, x2:Single, y2:Single, boundingBox = false):Brush {
		return new Brush(BlincNative.blinc_brush_gradient(false, x1, y1, x2, y2, boundingBox));
	}

	/** A radial gradient about `(cx, cy)` of `radius`, with no stops yet; `boundingBox` as for `linear`. **/
	public static function radial(cx:Single, cy:Single, radius:Single, boundingBox = false):Brush {
		return new Brush(BlincNative.blinc_brush_gradient(true, cx, cy, radius, 0, boundingBox));
	}

	/** Adds a stop at `offset`, 0 to 1, to this gradient; returns it. Set it on a node after its last stop. **/
	public function stop(offset:Single, hex:Int, alpha:Single = 1.0):Brush {
		BlincNative.blinc_brush_gradient_stop(ptr, offset, hex, alpha);
		return this;
	}

	/** A two-stop linear gradient from `fromHex` at the start point to `toHex` at the end; `linear` takes any stops. **/
	public static inline function linearGradient(startX:Single, startY:Single, endX:Single, endY:Single, fromHex:Int, fromAlpha:Single = 1.0, toHex:Int,
			toAlpha:Single = 1.0):Brush {
		return new Brush(BlincNative.blinc_brush_linear_gradient(startX, startY, endX, endY, fromHex, fromAlpha, toHex, toAlpha));
	}
}
