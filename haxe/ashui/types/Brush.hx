package ashui.types;

import ashui.core.Utf8;
import ashui.core.externs.BlincNative;

enum abstract ImageFit(Int) from Int to Int {
	var Cover = 0;
	var Contain = 1;
	var Fill = 2;
	var Tile = 3;
}

class Brush implements IValue {
	public var ptr(default, null):hl.Abstract<"blinc_value">;

	/** A solid brush's colour, `0xRRGGBB`, and alpha; -1 for any other brush. **/
	public var solidRgb(default, null) = -1;
	public var solidAlpha(default, null) = 1.0;

	private function new(ptr:hl.Abstract<"blinc_value">) {
		this.ptr = ptr;
	}

	// 1. Solid Color
	public static function solid(hex:Int, alpha:Single = 1.0):Brush {
		var brush = new Brush(BlincNative.blinc_brush_solid(hex, alpha));
		brush.solidRgb = hex & 0xFFFFFF;
		brush.solidAlpha = alpha;
		return brush;
	}

	// 2. Glass (iOS/macOS style frosted background)
	public static inline function glass(blur:Single, tintHex:Int, tintAlpha:Single = 0.1, simple:Bool = false):Brush {
		return new Brush(BlincNative.blinc_brush_glass(blur, tintHex, tintAlpha, simple ? 1 : 0));
	}

	// 3. Pure Blur (Just blurs content behind it)
	public static inline function blur(radius:Single):Brush {
		return new Brush(BlincNative.blinc_brush_blur(radius));
	}

	// 4. Image Background
	public static inline function image(url:String, fit:ImageFit = Cover):Brush {
		return new Brush(BlincNative.blinc_brush_image(Utf8.encode(url), fit));
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

	// 5. Linear Gradient
	public static inline function linearGradient(startX:Single, startY:Single, endX:Single, endY:Single, fromHex:Int, fromAlpha:Single = 1.0, toHex:Int,
			toAlpha:Single = 1.0):Brush {
		return new Brush(BlincNative.blinc_brush_linear_gradient(startX, startY, endX, endY, fromHex, fromAlpha, toHex, toAlpha));
	}
}
