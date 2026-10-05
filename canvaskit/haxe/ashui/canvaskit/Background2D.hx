package ashui.canvaskit;

import ashui.draw.DrawContext;
import ashui.types.Brush;

/** The pattern a `Background2D` draws. **/
enum BackgroundPattern {
	None;

	/** A dot at every crossing of the grid. **/
	Dots;

	/** Lines along the grid. **/
	Grid;

	/** Lines at 45° both ways. **/
	Crosshatch;
}

/**
	A 2D canvas's background: a pattern every `spacing` content units, in
	`color` (`0xRRGGBB`) at `alpha`. Dots are `size` screen pixels across
	and lines `size` screen pixels wide at any zoom. As the view zooms out
	and the pattern grows dense, every `coarsen`-th crossing is kept and the
	rest fade out, so it never becomes a solid wash and never jumps from one
	density to the next. The GPU draws it (`Brush.pattern`), so it costs the
	same at any zoom.

	```haxe
	<canvas-kit background={Background2D.dots(0x8a8f98)} />
	```
**/
class Background2D {
	public final pattern:BackgroundPattern;
	public final spacing:Float;
	public final color:Int;
	public final alpha:Float;
	public final size:Float;

	/** How many crossings of one level make one of the next, coarser, level. **/
	public final coarsen:Int;

	/** How close together, in screen pixels, crossings may come before the finer level has faded out. **/
	public final minGap:Float;

	final brush:Null<Brush>;

	public function new(pattern:BackgroundPattern, spacing = 24.0, color = 0x8a8f98, alpha = 0.5, size = 1.5, coarsen = 4, minGap = 8.0) {
		this.pattern = pattern;
		this.spacing = spacing;
		this.color = color;
		this.alpha = alpha;
		this.size = size;
		this.coarsen = coarsen < 2 ? 2 : coarsen;
		this.minGap = minGap;
		var kind:Null<PatternKind> = switch pattern {
			case Dots: PatternKind.Dots;
			case Grid: PatternKind.Lines;
			case Crosshatch: PatternKind.Crosshatch;
			case None: null;
		}
		brush = kind == null ? null : Brush.pattern(kind, color, alpha, spacing, size, this.coarsen, minGap);
	}

	public static function dots(color = 0x8a8f98, spacing = 24.0, size = 2.0):Background2D
		return new Background2D(Dots, spacing, color, 0.6, size);

	public static function grid(color = 0x8a8f98, spacing = 24.0, width = 1.0):Background2D
		return new Background2D(Grid, spacing, color, 0.25, width);

	public static function crosshatch(color = 0x8a8f98, spacing = 24.0, width = 1.0):Background2D
		return new Background2D(Crosshatch, spacing, color, 0.2, width);

	/** Draws the pattern over the content rect `(x0, y0)` to `(x1, y1)`, the part in view, in content coordinates. **/
	public function draw(ctx:DrawContext, x0:Float, y0:Float, x1:Float, y1:Float, zoom:Float):Void
		if (brush != null && x1 > x0 && y1 > y0)
			ctx.fillRect(x0, y0, x1 - x0, y1 - y0, brush);
}
