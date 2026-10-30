package ashui.types;

import ashui.core.externs.Handles;
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

/** What a gradient does past its first and last stop: `Pad` holds their colours, `Repeat` starts again, `Reflect` runs back. **/
enum abstract GradientSpread(Int) to Int {
	var Pad = 0;
	var Reflect = 1;
	var Repeat = 2;
}

/**
	Describes a gradient for custom drawing, such as a canvas fill.
	Linear gradients run from `(x1, y1)` to `(x2, y2)`. Radial gradients use
	center `(x1, y1)` and radius `x2`. With `boundingBox`, coordinates are fractions of the filled box.
	`matrix` places the gradient's own space in the filled shape's, so a radial one can be an ellipse;
	`spread` is what happens past the ends; `focal`, from -1 to 1, moves a radial gradient's
	focus from its center toward its edge along the gradient's x axis.
	Only canvas fills read these three; a node's background ignores them.
**/
typedef BrushGradient = {
	@:optional var matrix:ashui.draw.Affine;
	@:optional var spread:GradientSpread;
	@:optional var focal:Float;
	final radial:Bool;
	final x1:Float;
	final y1:Float;
	final x2:Float;
	final y2:Float;
	final boundingBox:Bool;
	final stops:Array<BrushStop>;
}

/** Which axes an image brush repeats along. **/
enum abstract ImageRepeat(Int) to Int {
	var NoRepeat = 0;
	var RepeatX = 1;
	var RepeatY = 2;
	var Repeat = 3;
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
	Describes a canvas pattern with `spacing` in drawing units.
	Dots use an on-screen diameter of `size` pixels; lines use that width.
	Their screen size stays constant when zooming.

	When the pattern spacing approaches `minGap` pixels on screen,
	intermediate marks fade out. Only every `coarsen`-th mark remains.
**/
typedef BrushPattern = {
	final kind:PatternKind;
	final spacing:Float;
	final size:Float;
	final coarsen:Int;
	final minGap:Float;
}

/**
	A bitmap fill of a canvas shape: `matrix` places the bitmap's pixels in the shape's space, `repeat`
	says along which axes it tiles (it is held at its edge on the others), and `smooth` filters between its pixels.
**/
typedef BitmapFill = {
	final bitmap:Bitmap;
	final matrix:Null<ashui.draw.Affine>;
	final repeat:ImageRepeat;
	final smooth:Bool;
}

/**
	What fills a box, as a node's `Prop.Background`: a solid colour, a
	gradient, an image, or what is behind the box blurred.
**/
class Brush implements IValue {
	public var ptr(default, null):ValueHandle;

	/** A solid brush's colour, `0xRRGGBB`, and alpha; -1 for any other brush. **/
	public var solidRgb(default, null) = -1;

	public var solidAlpha(default, null) = 1.0;

	/** A gradient's description; null for any other brush. **/
	public var gradient(default, null):Null<BrushGradient> = null;

	/** A bitmap fill's description; null for any other brush. **/
	public var bitmapFill(default, null):Null<BitmapFill> = null;

	/** A pattern's description; null for any other brush. **/
	public var repeat(default, null):Null<BrushPattern> = null;

	private function new(ptr:ValueHandle) {
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
		Creates a glass brush from the backdrop, with blur and a colored tint.

		- `blur`: backdrop blur radius.
		- `tintHex` and `tintAlpha`: tint color and opacity.
		- `simple`: plain frosting without refraction, highlights or a bevel.
		- `noise`: grain strength, typically 0–0.1.
		- `aberration`: RGB separation, from 0 (none) to 1 (strong). Default 0.3.
		- `bevel`: rim width, refraction and highlight strength, from 0 to 1.
		  Default 1. Zero removes the rim entirely.
		- `inset`: bends the rim inward instead of outward.

		Aberration controls color separation independently of bevel strength.
		Simple glass ignores rim settings.
	**/
	public static inline function glass(blur:Single, tintHex:Int, tintAlpha:Single = 0.1, simple:Bool = false, noise:Single = 0, aberration:Single = 0.3,
			bevel:Single = 1, inset:Bool = false):Brush {
		var brush = new Brush(BlincNative.blinc_brush_glass(blur, tintHex, tintAlpha, simple ? 1 : 0, noise));
		BlincNative.blinc_brush_glass_aberration(brush.ptr, aberration);
		BlincNative.blinc_brush_glass_bevel(brush.ptr, bevel, inset);
		return brush;
	}

	/**
		What is behind the box blurred by `radius`, then `tintHex` at
		`tintAlpha` painted over it, as CSS's `backdrop-filter: blur()` under
		a translucent background colour.
	**/
	public static inline function blur(radius:Single, tintHex:Int = 0, tintAlpha:Single = 0):Brush {
		return new Brush(BlincNative.blinc_brush_blur(radius, tintHex, tintAlpha));
	}

	/** The image at `url` filling the box, fitted by `fit`. Bitmap position and repeat use the whole-image atlas mapping. **/
	public static function image(url:String, fit:ImageFit = Cover, ?position:ImagePosition, ?repeat:ImageRepeat):Brush {
		var brush = new Brush(BlincNative.blinc_brush_image(Utf8.encode(url), fit));
		if (position != null || repeat != null) {
			var p:ImagePosition = position == null ? {
				x: 0.5,
				y: 0.5,
				offsetX: 0.0,
				offsetY: 0.0
			} : position;
			BlincNative.blinc_brush_image_mapping(brush.ptr, p.x, p.y, p.offsetX, p.offsetY, repeat == null ? (fit == Tile ? Repeat : NoRepeat) : repeat);
		}
		return brush;
	}

	/** `bitmap` filling the box, fitted by `fit`, under its border and clipped to its corners, as CSS's `background-image`. **/
	public static function bitmap(bitmap:Bitmap, fit:ImageFit = Cover, ?position:ImagePosition, ?repeat:ImageRepeat):Brush {
		return image("ashui:bitmap:" + bitmap.slotFor(fit), fit, position, repeat);
	}

	/**
		`bitmap` as the fill of a canvas shape, as an OpenFL bitmap fill is: `matrix` places its pixels in the shape's
		space (none puts its top-left at the origin at its own size), `repeat` tiles it (`Repeat` by default), `smooth`
		filters it. As a node's background it fills the box, as `bitmap(b, Fill)` does.
	**/
	public static function bitmapPattern(bitmap:Bitmap, ?matrix:ashui.draw.Affine, repeat:ImageRepeat = Repeat, smooth = true):Brush {
		var brush = Brush.bitmap(bitmap, Fill);
		brush.bitmapFill = {bitmap: bitmap, matrix: matrix, repeat: repeat, smooth: smooth};
		return brush;
	}

	/**
		A linear gradient from `(x1, y1)` to `(x2, y2)` with no stops yet; add
		them with `stop`, in order. With `boundingBox` the points are fractions
		of the box it fills, else pixels from the box's corner.
	**/
	public static function linear(x1:Single, y1:Single, x2:Single, y2:Single, boundingBox = false):Brush {
		var brush = new Brush(BlincNative.blinc_brush_gradient(false, x1, y1, x2, y2, boundingBox));
		brush.gradient = {
			radial: false,
			x1: x1,
			y1: y1,
			x2: x2,
			y2: y2,
			boundingBox: boundingBox,
			stops: []
		};
		return brush;
	}

	/** A radial gradient about `(cx, cy)` of `radius`, with no stops yet; `boundingBox` as for `linear`. **/
	public static function radial(cx:Single, cy:Single, radius:Single, boundingBox = false):Brush {
		var brush = new Brush(BlincNative.blinc_brush_gradient(true, cx, cy, radius, 0, boundingBox));
		brush.gradient = {
			radial: true,
			x1: cx,
			y1: cy,
			x2: radius,
			y2: 0,
			boundingBox: boundingBox,
			stops: []
		};
		return brush;
	}

	/** Adds a stop at `offset`, 0 to 1, to this gradient; returns it. Set it on a node after its last stop. **/
	public function stop(offset:Single, hex:Int, alpha:Single = 1.0):Brush {
		BlincNative.blinc_brush_gradient_stop(ptr, offset, hex, alpha);
		if (gradient != null)
			gradient.stops.push({offset: offset, rgb: hex & 0xFFFFFF, alpha: alpha});
		return this;
	}

	/** Places this gradient's space in the filled shape's by `a b c d e f`, as a canvas `Affine` does; returns it. **/
	public function placed(a:Float, b:Float, c:Float, d:Float, e:Float, f:Float):Brush {
		if (gradient != null)
			gradient.matrix = new ashui.draw.Affine(a, b, c, d, e, f);
		return this;
	}

	/** Sets what this gradient does past its first and last stop; returns it. **/
	public function spreading(spread:GradientSpread):Brush {
		if (gradient != null)
			gradient.spread = spread;
		return this;
	}

	/** Moves a radial gradient's focus, `ratio` of its radius from the center along the x axis, -1 to 1; returns it. **/
	public function focused(ratio:Float):Brush {
		if (gradient != null)
			gradient.focal = Math.max(-0.999, Math.min(0.999, ratio));
		return this;
	}

	/** A two-stop linear gradient from `fromHex` at the start point to `toHex` at the end; `linear` takes any stops. **/
	public static function linearGradient(startX:Single, startY:Single, endX:Single, endY:Single, fromHex:Int, fromAlpha:Single = 1.0, toHex:Int,
			toAlpha:Single = 1.0):Brush {
		var brush = new Brush(BlincNative.blinc_brush_linear_gradient(startX, startY, endX, endY, fromHex, fromAlpha, toHex, toAlpha));
		brush.gradient = {
			radial: false,
			x1: startX,
			y1: startY,
			x2: endX,
			y2: endY,
			boundingBox: false,
			stops: [
				{offset: 0, rgb: fromHex & 0xFFFFFF, alpha: fromAlpha},
				{offset: 1, rgb: toHex & 0xFFFFFF, alpha: toAlpha}
			]
		};
		return brush;
	}
}
