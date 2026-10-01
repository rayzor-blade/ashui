package ashui.types;

enum abstract ImageFit(Int) from Int to Int {
	var Cover = 0;
	var Contain = 1;
	var Fill = 2;
	var Tile = 3;
}

class Brush {
	public var ptr(default, null):hl.Abstract<"blinc_brush">;

	private function new(ptr:hl.Abstract<"blinc_brush">) {
		this.ptr = ptr;
		hl.Gc.setFinalizer(this, finalize);
	}

	// 1. Solid Color
	public static inline function solid(hex:Int, alpha:Single = 1.0):Brush {
		return new Brush(BlincTypesNative.hl_blinc_brush_solid(hex, alpha));
	}

	// 2. Glass (iOS/macOS style frosted background)
	public static inline function glass(blur:Single, tintHex:Int, tintAlpha:Single = 0.1, simple:Bool = false):Brush {
		return new Brush(BlincTypesNative.hl_blinc_brush_glass(blur, tintHex, tintAlpha, simple));
	}

	// 3. Pure Blur (Just blurs content behind it)
	public static inline function blur(radius:Single):Brush {
		return new Brush(BlincTypesNative.hl_blinc_brush_blur(radius));
	}

	// 4. Image Background
	public static inline function image(url:String, fit:ImageFit = Cover):Brush {
		// String.bytes safely passes the underlying UCS-2 / UTF-8 memory buffer to C
		return new Brush(BlincTypesNative.hl_blinc_brush_image(url.bytes, fit));
	}

	// 5. Linear Gradient
	public static inline function linearGradient(startX:Single, startY:Single, endX:Single, endY:Single, fromHex:Int, fromAlpha:Single = 1.0, toHex:Int,
			toAlpha:Single = 1.0):Brush {
		return new Brush(BlincTypesNative.hl_blinc_brush_linear_gradient(startX, startY, endX, endY, fromHex, fromAlpha, toHex, toAlpha));
	}

	static function finalize(obj:Brush) {
		BlincTypesNative.hl_blinc_brush_drop(obj.ptr);
	}
}
