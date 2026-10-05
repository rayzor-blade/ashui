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
	density to the next.

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

	public function new(pattern:BackgroundPattern, spacing = 24.0, color = 0x8a8f98, alpha = 0.5, size = 1.5, coarsen = 4, minGap = 8.0) {
		this.pattern = pattern;
		this.spacing = spacing;
		this.color = color;
		this.alpha = alpha;
		this.size = size;
		this.coarsen = coarsen < 2 ? 2 : coarsen;
		this.minGap = minGap;
	}

	public static function dots(color = 0x8a8f98, spacing = 24.0, size = 2.0):Background2D
		return new Background2D(Dots, spacing, color, 0.6, size);

	public static function grid(color = 0x8a8f98, spacing = 24.0, width = 1.0):Background2D
		return new Background2D(Grid, spacing, color, 0.25, width);

	public static function crosshatch(color = 0x8a8f98, spacing = 24.0, width = 1.0):Background2D
		return new Background2D(Crosshatch, spacing, color, 0.2, width);

	/** At most this many dots or lines are drawn a frame, whatever the zoom. **/
	static inline var LIMIT = 6000;

	/**
		Draws the pattern over the content rect `(x0, y0)` to `(x1, y1)`, the
		part in view, at `zoom`, in content coordinates.
	**/
	public function draw(ctx:DrawContext, x0:Float, y0:Float, x1:Float, y1:Float, zoom:Float):Void {
		if (pattern == None || zoom <= 0)
			return;
		// The finest level whose crossings are at least minGap apart on screen; the next finer one fades in above it.
		var step = spacing;
		while (step * zoom < minGap)
			step *= coarsen;
		var fine = step / coarsen;
		// 0 when the finer level's crossings are minGap apart, 1 when they are coarsen times that.
		var fade = fine * zoom < minGap ? 0.0 : Math.min(1, (fine * zoom - minGap) / (minGap * (coarsen - 1)));
		if (fine >= spacing && fade > 0.01)
			layer(ctx, x0, y0, x1, y1, zoom, fine, alpha * fade, step);
		layer(ctx, x0, y0, x1, y1, zoom, step, alpha, 0);
	}

	/** One level: every `step`, at `a`, leaving out what the coarser level `skip` (0 for none) draws. **/
	function layer(ctx:DrawContext, x0:Float, y0:Float, x1:Float, y1:Float, zoom:Float, step:Float, a:Float, skip:Float):Void {
		var brush = Brush.solid(color, a);
		var px = size / zoom;
		var i0 = Math.floor(x0 / step), i1 = Math.ceil(x1 / step), j0 = Math.floor(y0 / step), j1 = Math.ceil(y1 / step);
		inline function skipped(k:Int):Bool
			return skip > 0 && Math.abs(k * step / skip - Math.round(k * step / skip)) < 1e-6;
		switch pattern {
			case Dots:
				if ((i1 - i0 + 1) * (j1 - j0 + 1) > LIMIT)
					return;
				for (j in j0...j1 + 1)
					for (i in i0...i1 + 1)
						if (!(skipped(i) && skipped(j)))
							ctx.fillCircle(i * step, j * step, px / 2, brush);
			case Grid:
				if ((i1 - i0) + (j1 - j0) > LIMIT)
					return;
				for (i in i0...i1 + 1)
					if (!skipped(i))
						ctx.fillRect(i * step - px / 2, y0, px, y1 - y0, brush);
				for (j in j0...j1 + 1)
					if (!skipped(j))
						ctx.fillRect(x0, j * step - px / 2, x1 - x0, px, brush);
			case Crosshatch:
				// Lines x + y = k·step and x - y = k·step, each through the rect.
				var stroke = new ashui.draw.Stroke(px);
				var lo = Math.floor((x0 + y0) / step), hi = Math.ceil((x1 + y1) / step);
				var dlo = Math.floor((x0 - y1) / step), dhi = Math.ceil((x1 - y0) / step);
				if ((hi - lo) + (dhi - dlo) > LIMIT)
					return;
				ctx.pushClipRect(x0, y0, x1 - x0, y1 - y0);
				for (k in lo...hi + 1)
					if (!skipped(k))
						ctx.line(k * step - y0, y0, k * step - y1, y1, stroke, brush);
				for (k in dlo...dhi + 1)
					if (!skipped(k))
						ctx.line(k * step + y0, y0, k * step + y1, y1, stroke, brush);
				ctx.popClip();
			case None:
		}
	}
}
