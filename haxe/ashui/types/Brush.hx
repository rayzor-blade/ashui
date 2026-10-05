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

/** One colour of a gradient, at `offset` along it, 0 to 1. **/
typedef BrushStop = {
	final offset:Float;
	final rgb:Int;
	final alpha:Float;
}

/**
	A gradient as it was made, for code that paints it itself, as a canvas
	does: linear from `(x1, y1)` to `(x2, y2)`, or radial about `(x1, y1)`
	out to `x2`; in fractions of the box it fills when `boundingBox`.
**/
typedef BrushGradient = {
	final radial:Bool;
	final x1:Float;
	final y1:Float;
	final x2:Float;
	final y2:Float;
	final boundingBox:Bool;
	final stops:Array<BrushStop>;
}

/** The shape a pattern brush repeats. **/
enum abstract PatternKind(Int) to Int {
	/** A dot at every crossing of the grid. **/
	var Dots = 1;

	/** Lines along the grid. **/
	var Lines = 2;

	/** Lines at 45° both ways. **/
	var Crosshatch = 3;
}

/**
	A pattern as it was made, for a canvas to draw: `kind` every `spacing`
	units of the space it is drawn in, its dots `size` pixels across or its
	lines `size` pixels wide on screen, whatever the scale. Where the
	pattern would come closer together on screen than `minGap` pixels, only
	every `coarsen`-th line or dot is kept, and the ones in between fade out
	as it nears that limit.
**/
typedef BrushPattern = {
	final kind:PatternKind;
	final spacing:Float;
	final size:Float;
	final coarsen:Int;
	final minGap:Float;
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

	/** A gradient's description; null for any other brush. **/
	public var gradient(default, null):Null<BrushGradient> = null;

	/** A pattern's description; null for any other brush. **/
	public var repeat(default, null):Null<BrushPattern> = null;

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
		A repeating pattern in `hex` at `alpha`, for a canvas: dots, lines or
		crosshatch every `spacing` units, `size` screen pixels across, thinned
		as it is scaled down (see `BrushPattern`). The GPU draws it, so a
		shape filled with it costs the same however many dots or lines it
		holds. As a node's background it is only the plain colour.

		```haxe
		ctx.fillRect(0, 0, 2000, 2000, Brush.pattern(Dots, 0x8a8f98, 0.6, 24, 2));
		```
	**/
	public static function pattern(kind:PatternKind, hex:Int, alpha:Single = 1.0, spacing = 24.0, size = 1.5, coarsen = 4, minGap = 8.0):Brush {
		var brush = solid(hex, alpha);
		brush.repeat = {
			kind: kind,
			spacing: spacing,
			size: size,
			coarsen: coarsen < 2 ? 2 : coarsen,
			minGap: minGap
		};
		return brush;
	}

	/**
		Frosted glass, as iOS and macOS draw it: what is behind the box
		blurred by `blur` and tinted with `tintHex` at `tintAlpha`. `simple`
		is the plain frosting, without refraction, highlights or a bevel at
		the edge. `noise`, 0 to about 0.1, adds a frosted grain.
	**/
	public static inline function glass(blur:Single, tintHex:Int, tintAlpha:Single = 0.1, simple:Bool = false, noise:Single = 0):Brush {
		return new Brush(BlincNative.blinc_brush_glass(blur, tintHex, tintAlpha, simple ? 1 : 0, noise));
	}

	/**
		What is behind the box blurred by `radius`, then `tintHex` at
		`tintAlpha` painted over it, as CSS's `backdrop-filter: blur()` under
		a translucent background colour.
	**/
	public static inline function blur(radius:Single, tintHex:Int = 0, tintAlpha:Single = 0):Brush {
		return new Brush(BlincNative.blinc_brush_blur(radius, tintHex, tintAlpha));
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
		var brush = new Brush(BlincNative.blinc_brush_gradient(false, x1, y1, x2, y2, boundingBox));
		brush.gradient = {radial: false, x1: x1, y1: y1, x2: x2, y2: y2, boundingBox: boundingBox, stops: []};
		return brush;
	}

	/** A radial gradient about `(cx, cy)` of `radius`, with no stops yet; `boundingBox` as for `linear`. **/
	public static function radial(cx:Single, cy:Single, radius:Single, boundingBox = false):Brush {
		var brush = new Brush(BlincNative.blinc_brush_gradient(true, cx, cy, radius, 0, boundingBox));
		brush.gradient = {radial: true, x1: cx, y1: cy, x2: radius, y2: 0, boundingBox: boundingBox, stops: []};
		return brush;
	}

	/** Adds a stop at `offset`, 0 to 1, to this gradient; returns it. Set it on a node after its last stop. **/
	public function stop(offset:Single, hex:Int, alpha:Single = 1.0):Brush {
		BlincNative.blinc_brush_gradient_stop(ptr, offset, hex, alpha);
		if (gradient != null)
			gradient.stops.push({offset: offset, rgb: hex & 0xFFFFFF, alpha: alpha});
		return this;
	}

	/** A two-stop linear gradient from `fromHex` at the start point to `toHex` at the end; `linear` takes any stops. **/
	public static function linearGradient(startX:Single, startY:Single, endX:Single, endY:Single, fromHex:Int, fromAlpha:Single = 1.0, toHex:Int,
			toAlpha:Single = 1.0):Brush {
		var brush = new Brush(BlincNative.blinc_brush_linear_gradient(startX, startY, endX, endY, fromHex, fromAlpha, toHex, toAlpha));
		brush.gradient = {
			radial: false, x1: startX, y1: startY, x2: endX, y2: endY, boundingBox: false,
			stops: [{offset: 0, rgb: fromHex & 0xFFFFFF, alpha: fromAlpha}, {offset: 1, rgb: toHex & 0xFFFFFF, alpha: toAlpha}]
		};
		return brush;
	}
}
