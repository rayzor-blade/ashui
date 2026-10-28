package ashui.canvaskit;

import ashui.math.Vec3;

/**
	A centripetal Catmull-Rom curve through control points.
	Use for profiles and surface details, then `sample` points for a cage or
	path. Centripetal spacing avoids loops and overshoot between nearby points.

	`at(t)` runs from the first point at zero to the last at one, with equal
	parameter spans between neighboring control points. Closed splines
	continue from the last point back to the first.
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

	/** Number of curve spans between control points. **/
	public var spans(get, never):Int;

	function get_spans():Int
		return closed ? points.length : points.length - 1;

	/** Returns the curve point at `t` from zero to one. **/
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

	/** Returns the unit tangent direction at `t`. **/
	public function tangent(t:Float):Vec3 {
		var h = 1e-4;
		return at(Math.min(1, t + h)).sub(at(Math.max(0, t - h))).normalize();
	}

	/** Returns `count` sampled points including the curve start and end. **/
	public function sample(count:Int):Array<Vec3>
		return [for (i in 0...count) at(count < 2 ? 0 : i / (count - 1))];

	/** Returns a control point, wrapping for closed curves or linearly extrapolating beyond open ends. **/
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
