package ashui.draw;

/** One subpath cut into straight steps: its points, `[x0, y0, x1, y1, …]`, no two alike in a row, and whether it closes. **/
class Contour {
	public final points:Array<Float> = [];
	public var closed = false;

	public function new() {}

	public inline function count():Int
		return points.length >> 1;

	public inline function x(i:Int):Float
		return points[i << 1];

	public inline function y(i:Int):Float
		return points[(i << 1) + 1];

	/** Adds a point, unless it is where the last one is. **/
	public function add(px:Float, py:Float):Void {
		var n = points.length;
		if (n >= 2 && Math.abs(points[n - 2] - px) < 1e-9 && Math.abs(points[n - 1] - py) < 1e-9)
			return;
		points.push(px);
		points.push(py);
	}

	/** Twice the signed area, positive where the inside is to the left of the way it runs, in x right and y up terms. **/
	public function area2():Float {
		var n = count(), sum = 0.0;
		for (i in 0...n) {
			var j = (i + 1) % n;
			sum += x(i) * y(j) - x(j) * y(i);
		}
		return sum;
	}
}

/**
	Cuts a path into straight steps through a transform: curves and arcs
	are divided until no step strays from its curve by more than
	`tolerance`, measured after the transform, so a path drawn larger on
	screen gets more steps, never fewer than it looks smooth with.
**/
class Flatten {
	public static function path(path:Path, m:Affine, tolerance:Float):Array<Contour> {
		var out:Array<Contour> = [];
		var current:Null<Contour> = null;
		// The pen and the subpath's start, before the transform: arcs are worked out there.
		var px = 0.0, py = 0.0, sx = 0.0, sy = 0.0;
		inline function finish() {
			if (current != null && current.count() > 0)
				out.push(current);
			current = null;
		}
		function contour():Contour {
			if (current == null) {
				current = new Contour();
				current.add(m.x(px, py), m.y(px, py));
			}
			return current;
		}
		for (c in path.commands)
			switch c {
				case MoveTo(x, y):
					finish();
					px = sx = x;
					py = sy = y;
					current = new Contour();
					current.add(m.x(x, y), m.y(x, y));
				case LineTo(x, y):
					contour().add(m.x(x, y), m.y(x, y));
					px = x;
					py = y;
				case QuadTo(cx, cy, x, y):
					// As the cubic it is: its controls two thirds of the way to the quadratic's.
					cubic(contour(), m, px, py, px + (cx - px) * 2 / 3, py + (cy - py) * 2 / 3, x + (cx - x) * 2 / 3, y + (cy - y) * 2 / 3, x, y, tolerance);
					px = x;
					py = y;
				case CubicTo(c1x, c1y, c2x, c2y, x, y):
					cubic(contour(), m, px, py, c1x, c1y, c2x, c2y, x, y, tolerance);
					px = x;
					py = y;
				case ArcTo(rx, ry, rotation, large, sweep, x, y):
					arc(contour(), m, px, py, rx, ry, rotation, large, sweep, x, y, tolerance);
					px = x;
					py = y;
				case Close:
					if (current != null) {
						current.closed = true;
						// Its last point back at its first is the closing step itself.
						var n = current.count();
						if (n > 1 && Math.abs(current.x(n - 1) - current.x(0)) < 1e-9 && Math.abs(current.y(n - 1) - current.y(0)) < 1e-9) {
							current.points.pop();
							current.points.pop();
						}
					}
					finish();
					px = sx;
					py = sy;
			}
		finish();
		return out;
	}

	/** A cubic from `(x0, y0)`, its points taken through `m` first, as Béziers are kept by affine maps. **/
	static function cubic(c:Contour, m:Affine, x0:Float, y0:Float, x1:Float, y1:Float, x2:Float, y2:Float, x3:Float, y3:Float,
			tolerance:Float):Void
		subdivide(c, m.x(x0, y0), m.y(x0, y0), m.x(x1, y1), m.y(x1, y1), m.x(x2, y2), m.y(x2, y2), m.x(x3, y3), m.y(x3, y3), tolerance, 0);

	/** Halves the curve until its controls lie within `tolerance` of its chord, then steps to its end. **/
	static function subdivide(c:Contour, x0:Float, y0:Float, x1:Float, y1:Float, x2:Float, y2:Float, x3:Float, y3:Float, tolerance:Float,
			depth:Int):Void {
		var dx = x3 - x0, dy = y3 - y0;
		var d1 = Math.abs((x1 - x3) * dy - (y1 - y3) * dx);
		var d2 = Math.abs((x2 - x3) * dy - (y2 - y3) * dx);
		var chord2 = dx * dx + dy * dy;
		// The curve strays from its chord by at most three quarters of its controls' farthest distance from it; with no chord, by their spread.
		var far = Math.max(d1, d2);
		var flat = chord2 > 1e-18 ? far * far * 0.5625 <= tolerance * tolerance * chord2 : Math.max(Math.abs(x1 - x0)
			+ Math.abs(y1 - y0), Math.abs(x2 - x0) + Math.abs(y2 - y0)) <= tolerance;
		if (flat || depth >= 16) {
			c.add(x3, y3);
			return;
		}
		var x01 = (x0 + x1) / 2, y01 = (y0 + y1) / 2;
		var x12 = (x1 + x2) / 2, y12 = (y1 + y2) / 2;
		var x23 = (x2 + x3) / 2, y23 = (y2 + y3) / 2;
		var xa = (x01 + x12) / 2, ya = (y01 + y12) / 2;
		var xb = (x12 + x23) / 2, yb = (y12 + y23) / 2;
		var xm = (xa + xb) / 2, ym = (ya + yb) / 2;
		subdivide(c, x0, y0, x01, y01, xa, ya, xm, ym, tolerance, depth + 1);
		subdivide(c, xm, ym, xb, yb, x23, y23, x3, y3, tolerance, depth + 1);
	}

	/**
		SVG's elliptical arc from `(x1, y1)` to `(x2, y2)`, as cubics of a
		quarter turn or less: its centre found as SVG's implementation notes
		do, its radii grown if they cannot reach.
	**/
	static function arc(c:Contour, m:Affine, x1:Float, y1:Float, rx:Float, ry:Float, rotation:Float, large:Bool, sweep:Bool, x2:Float,
			y2:Float, tolerance:Float):Void {
		rx = Math.abs(rx);
		ry = Math.abs(ry);
		if (rx < 1e-12 || ry < 1e-12 || (x1 == x2 && y1 == y2)) {
			c.add(m.x(x2, y2), m.y(x2, y2));
			return;
		}
		var phi = rotation * Math.PI / 180, cos = Math.cos(phi), sin = Math.sin(phi);
		var dx2 = (x1 - x2) / 2, dy2 = (y1 - y2) / 2;
		var x1p = cos * dx2 + sin * dy2, y1p = -sin * dx2 + cos * dy2;
		var lambda = x1p * x1p / (rx * rx) + y1p * y1p / (ry * ry);
		if (lambda > 1) {
			rx *= Math.sqrt(lambda);
			ry *= Math.sqrt(lambda);
		}
		var num = rx * rx * ry * ry - rx * rx * y1p * y1p - ry * ry * x1p * x1p;
		var den = rx * rx * y1p * y1p + ry * ry * x1p * x1p;
		var coef = (large == sweep ? -1 : 1) * Math.sqrt(Math.max(0, num / den));
		var cxp = coef * rx * y1p / ry, cyp = -coef * ry * x1p / rx;
		var cx = cos * cxp - sin * cyp + (x1 + x2) / 2, cy = sin * cxp + cos * cyp + (y1 + y2) / 2;
		inline function angle(ux:Float, uy:Float, vx:Float, vy:Float)
			return Math.atan2(ux * vy - uy * vx, ux * vx + uy * vy);
		var ux = (x1p - cxp) / rx, uy = (y1p - cyp) / ry;
		var vx = (-x1p - cxp) / rx, vy = (-y1p - cyp) / ry;
		var start = angle(1, 0, ux, uy);
		var turn = angle(ux, uy, vx, vy);
		if (!sweep && turn > 0)
			turn -= Math.PI * 2;
		else if (sweep && turn < 0)
			turn += Math.PI * 2;
		var n = Math.ceil(Math.abs(turn) / (Math.PI / 2) - 1e-9);
		if (n < 1)
			n = 1;
		var step = turn / n;
		var k = 4 / 3 * Math.tan(step / 4);
		inline function px(a:Float)
			return cx + rx * Math.cos(a) * cos - ry * Math.sin(a) * sin;
		inline function py(a:Float)
			return cy + rx * Math.cos(a) * sin + ry * Math.sin(a) * cos;
		inline function tx(a:Float)
			return -rx * Math.sin(a) * cos - ry * Math.cos(a) * sin;
		inline function ty(a:Float)
			return -rx * Math.sin(a) * sin + ry * Math.cos(a) * cos;
		for (i in 0...n) {
			var a1 = start + i * step, a2 = a1 + step;
			var ex = i == n - 1 ? x2 : px(a2), ey = i == n - 1 ? y2 : py(a2);
			cubic(c, m, px(a1), py(a1), px(a1) + k * tx(a1), py(a1) + k * ty(a1), px(a2) - k * tx(a2), py(a2) - k * ty(a2), ex, ey, tolerance);
		}
	}
}
