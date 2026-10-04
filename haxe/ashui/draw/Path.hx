package ashui.draw;

import ashui.svg.PathData;
import ashui.svg.PathData.PathCommand;

/** Which parts of a path that crosses itself, or has paths inside it, are inside: by winding, or by crossings. **/
enum abstract FillRule(Int) {
	var NonZero = 0;
	var EvenOdd = 1;
}

/**
	An outline to fill or stroke, built step by step: `moveTo` starts a
	subpath, `lineTo`, `quadTo`, `cubicTo` and `arcTo` extend it, `close`
	joins it back to its start. Shapes add whole closed subpaths. The steps
	are SVG's path commands, so `Path.svg` reads a `d` attribute too. Each
	call returns the path, to chain.
**/
class Path {
	public final commands:Array<PathCommand> = [];

	/** Where the pen is, and where the subpath it is drawing began. **/
	var x = 0.0;

	var y = 0.0;
	var startX = 0.0;
	var startY = 0.0;

	public function new() {}

	/** The path SVG path data `d` draws. **/
	public static function svg(d:String):Path {
		var p = new Path();
		for (c in PathData.parse(d))
			p.add(c);
		return p;
	}

	public function add(c:PathCommand):Path {
		commands.push(c);
		switch c {
			case MoveTo(px, py):
				x = startX = px;
				y = startY = py;
			case LineTo(px, py) | CubicTo(_, _, _, _, px, py) | QuadTo(_, _, px, py) | ArcTo(_, _, _, _, _, px, py):
				x = px;
				y = py;
			case Close:
				x = startX;
				y = startY;
		}
		return this;
	}

	public function moveTo(x:Float, y:Float):Path
		return add(MoveTo(x, y));

	public function lineTo(x:Float, y:Float):Path
		return add(LineTo(x, y));

	public function quadTo(cx:Float, cy:Float, x:Float, y:Float):Path
		return add(QuadTo(cx, cy, x, y));

	public function cubicTo(c1x:Float, c1y:Float, c2x:Float, c2y:Float, x:Float, y:Float):Path
		return add(CubicTo(c1x, c1y, c2x, c2y, x, y));

	/** An elliptical arc to `(x, y)`, as SVG's `A`: radii, the ellipse turned by `rotation` degrees, which of the four arcs. **/
	public function arcTo(rx:Float, ry:Float, rotation:Float, largeArc:Bool, sweep:Bool, x:Float, y:Float):Path
		return add(ArcTo(rx, ry, rotation, largeArc, sweep, x, y));

	public function close():Path
		return add(Close);

	/**
		An arc of the circle about `(cx, cy)` of `radius`, from angle `start`
		to `end` in radians, clockwise on screen unless `counterclockwise`:
		a line from the pen to its start, or a new subpath if there is none.
	**/
	public function arc(cx:Float, cy:Float, radius:Float, start:Float, end:Float, counterclockwise = false):Path {
		var sx = cx + radius * Math.cos(start), sy = cy + radius * Math.sin(start);
		if (commands.length == 0 || commands[commands.length - 1].match(Close))
			moveTo(sx, sy);
		else
			lineTo(sx, sy);
		var sweep = counterclockwise ? start - end : end - start;
		if (sweep >= Math.PI * 2 - 1e-9) {
			// A whole turn: two halves, as one SVG arc cannot end where it starts.
			var mid = start + (counterclockwise ? -Math.PI : Math.PI);
			arcTo(radius, radius, 0, false, !counterclockwise, cx + radius * Math.cos(mid), cy + radius * Math.sin(mid));
			return arcTo(radius, radius, 0, false, !counterclockwise, sx, sy);
		}
		sweep = sweep % (Math.PI * 2);
		if (sweep < 0)
			sweep += Math.PI * 2;
		return arcTo(radius, radius, 0, sweep > Math.PI, !counterclockwise, cx + radius * Math.cos(end), cy + radius * Math.sin(end));
	}

	public function rect(x:Float, y:Float, w:Float, h:Float):Path
		return moveTo(x, y).lineTo(x + w, y).lineTo(x + w, y + h).lineTo(x, y + h).close();

	/** A rectangle with each corner rounded by `r`, kept to half the shorter side. **/
	public function roundedRect(x:Float, y:Float, w:Float, h:Float, r:Float):Path {
		r = Math.max(0, Math.min(r, Math.min(w, h) / 2));
		if (r == 0)
			return rect(x, y, w, h);
		return moveTo(x + r, y)
			.lineTo(x + w - r, y)
			.arcTo(r, r, 0, false, true, x + w, y + r)
			.lineTo(x + w, y + h - r)
			.arcTo(r, r, 0, false, true, x + w - r, y + h)
			.lineTo(x + r, y + h)
			.arcTo(r, r, 0, false, true, x, y + h - r)
			.lineTo(x, y + r)
			.arcTo(r, r, 0, false, true, x + r, y)
			.close();
	}

	public function ellipse(cx:Float, cy:Float, rx:Float, ry:Float):Path
		return moveTo(cx + rx, cy)
			.arcTo(rx, ry, 0, false, true, cx - rx, cy)
			.arcTo(rx, ry, 0, false, true, cx + rx, cy)
			.close();

	public inline function circle(cx:Float, cy:Float, r:Float):Path
		return ellipse(cx, cy, r, r);
}
