package ashui.draw;

import ashui.draw.Flatten.Contour;
import ashui.draw.Path.FillRule;
import ashui.draw.Sweep;

/**
	Turns contours into triangles: a fill as its inside, a stroke as the
	band around its line, each with a fringe `aa` wide, its coverage
	falling from 1 to 0 outward, which antialiases the edge without
	multisampling. Nothing a fill or a stroke covers is covered twice by
	its fill, so a translucent fill is even.
**/
class Tessellate {
	/**
		The inside of `contours`, closed whatever they say, by `rule`, cut
		into trapezoids by a sweep down the page, then the fringe outside
		its edges.

		The sweep cuts the plane into bands at every vertex and every point
		where edges cross, so no two edges cross inside a band. Across a
		band the edges are walked left to right, counting how many times
		the contours wind round; where the count is inside by `rule`, the
		space to the next edge is a trapezoid. That one walk deals with
		holes, paths inside paths, paths that cross themselves and each
		other, and either rule alike; its trapezoids never overlap, and
		meet exactly, as each edge's position is worked out the same way
		by the bands either side of it. Where the count changes from inside
		to outside across an edge, that piece of edge is the shape's edge,
		and gets the fringe on its outer side; a trapezoid's vertices carry
		their distances inside the shape's edges it lies along, so the
		pixels just inside them are covered by how far inside they are.
	**/
	public static function fill(contours:Array<Contour>, rule:FillRule, aa:Float, mesh:Mesh, coverage = 1.0):Void {
		var rings = [for (c in contours) if (c.count() >= 3) c];
		if (rings.length == 0)
			return;
		Sweep.fill(rings, rule, aa, mesh, coverage);
	}

	/** Where a corner between edges of outward normals `a` and `b` moves out to, for the strip to keep its width: a little at most. **/
	@:allow(ashui.draw)
	static function miter(ax:Float, ay:Float, bx:Float, by:Float):Array<Float> {
		var mx = ax + bx, my = ay + by;
		var ml = Math.sqrt(mx * mx + my * my);
		if (ml < 1e-9)
			return [ax, ay];
		mx /= ml;
		my /= ml;
		var k = 1 / Math.max(mx * ax + my * ay, 0.25);
		return [mx * k, my * k];
	}

	static function rightNormal(ax:Float, ay:Float, bx:Float, by:Float):Array<Float> {
		var dx = bx - ax, dy = by - ay;
		var l = Math.sqrt(dx * dx + dy * dy);
		if (l < 1e-12)
			return [0.0, 0.0];
		return [dy / l, -dx / l];
	}

	static inline function cross(ax:Float, ay:Float, bx:Float, by:Float, px:Float, py:Float):Float
		return (bx - ax) * (py - ay) - (px - ax) * (by - ay);

	/**
		The band along each contour, `stroke.width` wide times `scale`, the
		contours' units to a unit of the stroke's (its dashes scaled the
		same), its joins and caps as `stroke` says, with a fringe `aa` wide
		at its sides and ends. A band narrower than the fringe is drawn as
		wide as it, fainter by as much, so a hairline keeps its weight.
	**/
	public static function stroke(contours:Array<Contour>, stroke:Stroke, scale:Float, aa:Float, mesh:Mesh, coverage = 1.0):Void {
		var width = stroke.width * scale;
		if (width <= 0)
			return;
		var c = coverage;
		if (width < aa) {
			c *= width / aa;
			width = aa;
		}
		var half = width / 2;
		var inner = Math.max(half - aa / 2, 0), outer = half + aa / 2;
		var lines = stroke.dash.length > 0 ? dashed(contours, [for (d in stroke.dash) d * scale], stroke.dashOffset * scale) : contours;
		for (line in lines)
			band(line, stroke, inner, outer, aa, mesh, c);
	}

	/** The contours cut into dashes: open pieces of the dash lengths, the gaps between left out. **/
	static function dashed(contours:Array<Contour>, pattern:Array<Float>, offset:Float):Array<Contour> {
		var total = 0.0;
		for (d in pattern)
			total += Math.max(d, 0);
		if (total <= 0)
			return contours;
		// An odd pattern repeats twice over, as SVG's does, so dashes and gaps alternate.
		var p = pattern.length % 2 == 1 ? pattern.concat(pattern) : pattern;
		var out:Array<Contour> = [];
		for (c in contours) {
			var n = c.count();
			var steps = c.closed ? n : n - 1;
			var at = ((offset % total) + total) % total;
			var k = 0;
			while (at >= p[k]) {
				at -= p[k];
				k = (k + 1) % p.length;
			}
			// How far into dash or gap `k` the walk is.
			var into = at;
			var piece:Null<Contour> = null;
			if (k % 2 == 0) {
				piece = new Contour();
				piece.add(c.x(0), c.y(0));
			}
			for (s in 0...steps) {
				var i = s, j = (s + 1) % n;
				var x0 = c.x(i), y0 = c.y(i), x1 = c.x(j), y1 = c.y(j);
				var len = Math.sqrt((x1 - x0) * (x1 - x0) + (y1 - y0) * (y1 - y0));
				var done = 0.0;
				while (len - done > p[k] - into) {
					done += p[k] - into;
					var t = done / len;
					var x = x0 + (x1 - x0) * t, y = y0 + (y1 - y0) * t;
					if (piece != null) {
						piece.add(x, y);
						out.push(piece);
						piece = null;
					} else {
						piece = new Contour();
						piece.add(x, y);
					}
					k = (k + 1) % p.length;
					into = 0;
				}
				into += len - done;
				if (piece != null)
					piece.add(x1, y1);
			}
			if (piece != null && piece.count() > 1)
				out.push(piece);
		}
		return out;
	}

	/**
		One contour's band, as cross-sections along it, each four points
		across: the outer edge of the left fringe, coverage 0, the band's
		left and right edges, and the right fringe's outer edge. Sections in
		a row are joined by three quads. At a corner the side turned away
		from gets the join, its points swept round, cut across or met at a
		miter, and the side turned into meets at its miter.
	**/
	/**
		Sections, seven values each: the point, its left and right offsets
		each scaled to a unit of half-width, and 1, or 0 for a fringe end
		of no coverage. With the steps' unit directions and lengths, kept
		and reused from line to line, as a canvas strokes every frame.
	**/
	static final sections:Array<Float> = [];

	static final stepX:Array<Float> = [];
	static final stepY:Array<Float> = [];
	static final stepLength:Array<Float> = [];

	static inline function section(px:Float, py:Float, lx:Float, ly:Float, rx:Float, ry:Float, covered = 1.0):Void {
		sections.push(px);
		sections.push(py);
		sections.push(lx);
		sections.push(ly);
		sections.push(rx);
		sections.push(ry);
		sections.push(covered);
	}

	static function band(line:Contour, stroke:Stroke, inner:Float, outer:Float, aa:Float, mesh:Mesh, c:Float):Void {
		var n = line.count();
		if (n == 0)
			return;
		if (n == 1) {
			// A dot: round or square caps make one, a butt nothing.
			if (stroke.cap == Round)
				disc(line.x(0), line.y(0), inner, outer, mesh, c, aa);
			else if (stroke.cap == Square) {
				var r = new Contour();
				r.closed = true;
				var h = (inner + outer) / 2;
				r.add(line.x(0) - h, line.y(0) - h);
				r.add(line.x(0) + h, line.y(0) - h);
				r.add(line.x(0) + h, line.y(0) + h);
				r.add(line.x(0) - h, line.y(0) + h);
				fill([r], NonZero, aa, mesh, c);
			}
			return;
		}
		var closed = line.closed && n > 2;
		// Unit directions and lengths of the steps.
		var steps = closed ? n : n - 1;
		stepX.resize(0);
		stepY.resize(0);
		stepLength.resize(0);
		for (s in 0...steps) {
			var j = (s + 1) % n;
			var ex = line.x(j) - line.x(s), ey = line.y(j) - line.y(s);
			var l = Math.sqrt(ex * ex + ey * ey);
			stepX.push(ex / l);
			stepY.push(ey / l);
			stepLength.push(l);
		}
		sections.resize(0);
		if (closed) {
			for (i in 0...n)
				join(line, stroke, i, (i + n - 1) % n, i, outer, aa);
		} else {
			// The start: pushed back for a square cap, its end fringe a step behind it.
			var sx = line.x(0), sy = line.y(0), ux = stepX[0], uy = stepY[0];
			var back = stroke.cap == Square ? (inner + outer) / 2 : 0.0;
			if (stroke.cap == Round)
				cap(sx, sy, -ux, -uy, inner, outer, mesh, c, aa);
			else
				section(sx - ux * (back + aa), sy - uy * (back + aa), -uy, ux, uy, -ux, 0);
			section(sx - ux * back, sy - uy * back, -uy, ux, uy, -ux);
			for (i in 1...n - 1)
				join(line, stroke, i, i - 1, i, outer, aa);
			var ex = line.x(n - 1), ey = line.y(n - 1), vx = stepX[steps - 1], vy = stepY[steps - 1];
			section(ex + vx * back, ey + vy * back, -vy, vx, vy, -vx);
			if (stroke.cap == Round)
				cap(ex, ey, vx, vy, inner, outer, mesh, c, aa);
			else
				section(ex + vx * (back + aa), ey + vy * (back + aa), -vy, vx, vy, -vx, 0);
		}
		var count = Std.int(sections.length / 7);
		var links = closed ? count : count - 1;
		for (s in 0...links)
			strip(s * 7, ((s + 1) % count) * 7, inner, outer, mesh, c);
	}

	/**
		The sections at the corner of `line` at point `i`, between steps
		`d0` and `d1`: the side turned away from gets the join, its points
		swept round, cut across or met at a miter; the side turned into
		meets at its miter, no farther than its steps allow.
	**/
	static function join(line:Contour, stroke:Stroke, i:Int, d0:Int, d1:Int, outer:Float, aa:Float):Void {
		var px = line.x(i), py = line.y(i);
		// Left normals of the step in and the step out.
		var n0x = -stepY[d0], n0y = stepX[d0], n1x = -stepY[d1], n1y = stepX[d1];
		var turn = stepX[d0] * stepY[d1] - stepY[d0] * stepX[d1];
		var dot = stepX[d0] * stepX[d1] + stepY[d0] * stepY[d1];
		var mx = n0x + n1x, my = n0y + n1y;
		var ml = Math.sqrt(mx * mx + my * my);
		if (Math.abs(turn) < 1e-9 && dot > 0 || ml < 1e-9) {
			section(px, py, n0x, n0y, -n0x, -n0y);
			return;
		}
		mx /= ml;
		my /= ml;
		var k = 1 / Math.max(mx * n0x + my * n0y, 1e-6);
		var reach = Math.min(stepLength[d0], stepLength[d1]) / Math.max(outer, 1e-9);
		var ki = Math.min(k, Math.max(1, reach));
		// Turning left in these terms, the right side is the outside of the corner.
		var outsideRight = turn > 0;
		var ix = (outsideRight ? mx : -mx) * ki, iy = (outsideRight ? my : -my) * ki;
		inline function put(ox:Float, oy:Float)
			if (outsideRight) section(px, py, ix, iy, ox, oy) else section(px, py, ox, oy, ix, iy);
		var s = outsideRight ? -1.0 : 1.0;
		switch stroke.join {
			case Miter if (k <= stroke.miterLimit):
				put(s * mx * k, s * my * k);
			case Round:
				var a0 = Math.atan2(s * n0y, s * n0x), a1 = Math.atan2(s * n1y, s * n1x);
				var sweep = a1 - a0;
				while (sweep > Math.PI)
					sweep -= Math.PI * 2;
				while (sweep < -Math.PI)
					sweep += Math.PI * 2;
				var count = Math.ceil(Math.abs(sweep) / Math.max(Math.acos(Math.max(-1, 1 - aa * 0.1 / Math.max(outer, 1e-9))) * 2, 0.05));
				count = Std.int(Math.max(1, Math.min(count, 64)));
				for (t in 0...count + 1) {
					var a = a0 + sweep * t / count;
					put(Math.cos(a), Math.sin(a));
				}
			case _:
				put(s * n0x, s * n0y);
				put(s * n1x, s * n1y);
		}
	}

	/** The three quads from the section at `a` to the one at `b`: left fringe, band, right fringe. A fringe end has coverage 0 across. **/
	static function strip(a:Int, b:Int, inner:Float, outer:Float, mesh:Mesh, c:Float):Void {
		var f = sections;
		var ca = c * f[a + 6], cb = c * f[b + 6];
		inline function px(s:Int, side:Int, d:Float)
			return f[s] + f[s + 2 + side * 2] * d;
		inline function py(s:Int, side:Int, d:Float)
			return f[s + 1] + f[s + 3 + side * 2] * d;
		// Left fringe.
		mesh.quad(px(a, 0, outer), py(a, 0, outer), 0, px(a, 0, inner), py(a, 0, inner), ca, px(b, 0, inner), py(b, 0, inner), cb, px(b, 0, outer),
			py(b, 0, outer), 0);
		// The band between its edges.
		mesh.quad(px(a, 0, inner), py(a, 0, inner), ca, px(a, 1, inner), py(a, 1, inner), ca, px(b, 1, inner), py(b, 1, inner), cb, px(b, 0, inner),
			py(b, 0, inner), cb);
		// Right fringe.
		mesh.quad(px(a, 1, inner), py(a, 1, inner), ca, px(a, 1, outer), py(a, 1, outer), 0, px(b, 1, outer), py(b, 1, outer), 0, px(b, 1, inner),
			py(b, 1, inner), cb);
	}

	/** A round cap: a half disc beyond `(px, py)` the way `(ux, uy)` points, with its fringe. **/
	static function cap(px:Float, py:Float, ux:Float, uy:Float, inner:Float, outer:Float, mesh:Mesh, c:Float, aa:Float):Void {
		var a0 = Math.atan2(-ux, uy);
		arcFan(px, py, a0, Math.PI, inner, outer, mesh, c, aa);
	}

	/** A dot: a whole disc with its fringe. **/
	static function disc(px:Float, py:Float, inner:Float, outer:Float, mesh:Mesh, c:Float, aa:Float):Void
		arcFan(px, py, 0, Math.PI * 2, inner, outer, mesh, c, aa);

	/** A fan of the disc's sector from angle `start` through `sweep`, with the fringe ring around it. **/
	static function arcFan(px:Float, py:Float, start:Float, sweep:Float, inner:Float, outer:Float, mesh:Mesh, c:Float, aa:Float):Void {
		var steps = Std.int(Math.max(4, Math.min(64, Math.ceil(sweep / Math.max(Math.acos(Math.max(-1, 1 - 0.1 * aa / Math.max(outer, 1e-9))) * 2, 0.05)))));
		for (t in 0...steps) {
			var a = start + sweep * t / steps, b = start + sweep * (t + 1) / steps;
			var ca = Math.cos(a), sa = Math.sin(a), cb = Math.cos(b), sb = Math.sin(b);
			if (inner > 0)
				mesh.triangle(px, py, c, px + ca * inner, py + sa * inner, c, px + cb * inner, py + sb * inner, c);
			mesh.quad(px + ca * inner, py + sa * inner, c, px + ca * outer, py + sa * outer, 0, px + cb * outer, py + sb * outer, 0, px + cb * inner,
				py + sb * inner, c);
		}
	}
}
