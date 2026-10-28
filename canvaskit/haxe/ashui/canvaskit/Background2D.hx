package ashui.canvaskit;

import ashui.draw.DrawContext;
import ashui.types.Brush;

/** Pattern drawn by a 2D canvas background. **/
enum BackgroundPattern {
	None;

	/** Dots at grid intersections. **/
	Dots;

	/** Horizontal and vertical grid lines. **/
	Grid;

	/** Diagonal lines in both 45-degree directions. **/
	Crosshatch;
}

/**
	A GPU-drawn canvas pattern that follows pan and zoom.

	`spacing` uses content units; `size` uses screen pixels so dots and lines
	keep their visual width while zooming. `color` is `0xRRGGBB` with `alpha`.
	Dense patterns fade between levels, keeping every `coarsen`-th grid
	intersection instead of turning into a solid fill. Rendering uses
	`Brush.pattern` with fixed drawing cost across zoom levels.

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

	/** Grid-spacing multiplier between detail levels. **/
	public final coarsen:Int;

	/** Minimum screen-pixel spacing before the finer pattern level fully fades out. **/
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

	/** Draws the pattern over the visible content rectangle in content coordinates. **/
	public function draw(ctx:DrawContext, x0:Float, y0:Float, x1:Float, y1:Float, zoom:Float):Void
		if (brush != null && x1 > x0 && y1 > y0)
			ctx.fillRect(x0, y0, x1 - x0, y1 - y0, brush);
}
