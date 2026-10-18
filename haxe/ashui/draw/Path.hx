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

	/** The number of commands `signed` was worked out for. **/
	var signedFor = -1;

	var signed = 0;

	/**
		A number that paths with the same commands share and others seldom do, worked out once for the commands it has and again
		if more are added: what a cache that finds a path again by what it contains asks first, and then `same`.
	**/
	public function signature():Int {
		if (signedFor != commands.length) {
			var h = 17;
			inline function mix(v:Float)
				h = h * 31 + Std.int(v * 64);
			for (c in commands) {
				switch c {
					case MoveTo(x, y):
						h = h * 31 + 1;
						mix(x);
						mix(y);
					case LineTo(x, y):
						h = h * 31 + 2;
						mix(x);
						mix(y);
					case CubicTo(x1, y1, x2, y2, x, y):
						h = h * 31 + 3;
						mix(x1);
						mix(y1);
						mix(x2);
						mix(y2);
						mix(x);
						mix(y);
					case QuadTo(x1, y1, x, y):
						h = h * 31 + 4;
						mix(x1);
						mix(y1);
						mix(x);
						mix(y);
					case ArcTo(rx, ry, rotation, largeArc, sweep, x, y):
						h = h * 31 + (largeArc ? 5 : 6) + (sweep ? 2 : 0);
						mix(rx);
						mix(ry);
						mix(rotation);
						mix(x);
						mix(y);
					case Close:
						h = h * 31 + 7;
				}
			}
			signed = h;
			signedFor = commands.length;
		}
		return signed;
	}

	/** Whether `a` and `b` have the same commands, in the same order. **/
	public static function same(a:Path, b:Path):Bool {
		if (a == b)
			return true;
		var x = a.commands, y = b.commands;
		if (x.length != y.length)
			return false;
		for (i in 0...x.length) {
			var equal = switch [x[i], y[i]] {
				case [MoveTo(x1, y1), MoveTo(x2, y2)] | [LineTo(x1, y1), LineTo(x2, y2)]: x1 == x2 && y1 == y2;
				case [CubicTo(a1, b1, c1, d1, e1, f1), CubicTo(a2, b2, c2, d2, e2, f2)]: a1 == a2 && b1 == b2 && c1 == c2 && d1 == d2 && e1 == e2 && f1 == f2;
				case [QuadTo(a1, b1, c1, d1), QuadTo(a2, b2, c2, d2)]: a1 == a2 && b1 == b2 && c1 == c2 && d1 == d2;
				case [ArcTo(a1, b1, c1, l1, s1, x1, y1), ArcTo(a2, b2, c2, l2, s2, x2, y2)]:
					a1 == a2 && b1 == b2 && c1 == c2 && l1 == l2 && s1 == s2 && x1 == x2 && y1 == y2;
				case [Close, Close]: true;
				case _: false;
			}
			if (!equal)
				return false;
		}
		return true;
	}

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
		var sx = cx + radius * Math.cos(start),
			sy = cy + radius * Math.sin(start);
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
		return moveTo(x + r,
			y).lineTo(x + w - r, y)
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
		return moveTo(cx + rx, cy).arcTo(rx, ry, 0, false, true, cx - rx, cy).arcTo(rx, ry, 0, false, true, cx + rx, cy).close();

	public inline function circle(cx:Float, cy:Float, r:Float):Path
		return ellipse(cx, cy, r, r);
}
