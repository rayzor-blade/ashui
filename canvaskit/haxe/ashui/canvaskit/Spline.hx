package ashui.canvaskit;

import ashui.math.Vec3;

/**
	A smooth curve through points: a centripetal Catmull-Rom spline, which
	passes through every point and does not loop or overshoot between points
	that are close together. Use it for a profile or a character line, then
	`sample` it into the points of a cage or a path.

	`at(t)` runs from the first point at 0 to the last at 1, each span
	between neighbouring points taking an equal share of `t`. A closed spline
	runs on from the last point back round to the first.
**/
class Spline {
	public final points:Array<Vec3>;
	public final closed:Bool;

	public function new(points:Array<Vec3>, closed = false) {
		if (points.length < 2)
			throw "a spline needs at least two points";
		this.points = points.copy();
		this.closed = closed;
	}

	/** How many spans the curve has between its points. **/
	public var spans(get, never):Int;

	function get_spans():Int
		return closed ? points.length : points.length - 1;

	/** The curve's point at `t`, 0 to 1. **/
	public function at(t:Float):Vec3 {
		var s = spans;
		var f = (t < 0 ? 0 : t > 1 ? 1 : t) * s;
		var i = Std.int(Math.min(Math.floor(f), s - 1));
		var u = f - i;
		var p0 = point(i - 1), p1 = point(i), p2 = point(i + 1), p3 = point(i + 2);
		// Knots spaced by the square root of each span's length: the centripetal parameterisation.
		var t1 = knot(p0, p1), t2 = t1 + knot(p1, p2), t3 = t2 + knot(p2, p3);
		var tt = t1 + (t2 - t1) * u;
		var a1 = p0.scale((t1 - tt) / t1).add(p1.scale(tt / t1));
		var a2 = p1.scale((t2 - tt) / (t2 - t1)).add(p2.scale((tt - t1) / (t2 - t1)));
		var a3 = p2.scale((t3 - tt) / (t3 - t2)).add(p3.scale((tt - t2) / (t3 - t2)));
		var b1 = a1.scale((t2 - tt) / t2).add(a2.scale(tt / t2));
		var b2 = a2.scale((t3 - tt) / (t3 - t1)).add(a3.scale((tt - t1) / (t3 - t1)));
		return b1.scale((t2 - tt) / (t2 - t1)).add(b2.scale((tt - t1) / (t2 - t1)));
	}

	/** The direction the curve runs at `t`, a unit vector. **/
	public function tangent(t:Float):Vec3 {
		var h = 1e-4;
		return at(Math.min(1, t + h)).sub(at(Math.max(0, t - h))).normalize();
	}

	/** `count` points along the curve, the first at its start and the last at its end. **/
	public function sample(count:Int):Array<Vec3>
		return [for (i in 0...count) at(count < 2 ? 0 : i / (count - 1))];

	/** The point `i`, wrapping round a closed curve; past an open curve's ends, its end span carried on straight. **/
	function point(i:Int):Vec3 {
		var n = points.length;
		if (closed)
			return points[((i % n) + n) % n];
		if (i < 0)
			return points[0].scale(2).sub(points[1]);
		if (i >= n)
			return points[n - 1].scale(2).sub(points[n - 2]);
		return points[i];
	}

	static inline function knot(a:Vec3, b:Vec3):Float
		return Math.max(1e-6, Math.sqrt(a.distance(b)));
}
