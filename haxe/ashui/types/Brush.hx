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

	private function new(ptr:hl.Abstract<"blinc_value">) {
		this.ptr = ptr;
	}

	// 1. Solid Color
	public static inline function solid(hex:Int, alpha:Single = 1.0):Brush {
		return new Brush(BlincNative.blinc_brush_solid(hex, alpha));
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

	// 5. Linear Gradient
	public static inline function linearGradient(startX:Single, startY:Single, endX:Single, endY:Single, fromHex:Int, fromAlpha:Single = 1.0, toHex:Int,
			toAlpha:Single = 1.0):Brush {
		return new Brush(BlincNative.blinc_brush_linear_gradient(startX, startY, endX, endY, fromHex, fromAlpha, toHex, toAlpha));
	}
}
