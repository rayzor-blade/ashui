package ashui.draw;

import ashui.draw.Flatten.Contour;
import ashui.draw.Path.FillRule;

/**
	A fill cut into trapezoids by a sweep down the page (see
	`Tessellate.fill`), and the fringe along the pieces of edge where it
	ends. Edges are kept as the contours run, each with where it starts
	and ends, so corners between edges of the fill's edge get a miter.
**/
@:allow(ashui.draw)
class Sweep {
	static inline var EPS = 1e-9;

	final rule:FillRule;

	/** Each edge from its start to its end, as its contour runs. **/
	final sx:Array<Float> = [];

	final sy:Array<Float> = [];
	final ex:Array<Float> = [];
	final ey:Array<Float> = [];

	/** The edges before and after each in its contour. **/
	final prev:Array<Int> = [];

	final next:Array<Int> = [];

	/** Where each edge is the fill's edge: pieces `[top, bottom]` in y, and the side it is filled on, 1 for right on the page, -1 for left. **/
	final pieces:Array<Array<Float>> = [];

	/** The vertex ys, sorted, each once. **/
	final ys:Array<Float> = [];

	/** Level edges where the fill ends: `y, left x, right x`, and 1 where it is filled below, -1 above. **/
	final levels:Array<Array<Float>> = [];

	public function new(rings:Array<Contour>, rule:FillRule) {
		this.rule = rule;
		for (r in rings) {
			var n = r.count(), first = sx.length;
			for (i in 0...n) {
				var j = (i + 1) % n;
				sx.push(r.x(i));
				sy.push(r.y(i));
				ex.push(r.x(j));
				ey.push(r.y(j));
				prev.push(first + (i + n - 1) % n);
				next.push(first + j);
				pieces.push([]);
				ys.push(r.y(i));
			}
		}
		ys.sort((a, b) -> a < b ? -1 : a > b ? 1 : 0);
		var unique:Array<Float> = [];
		for (y in ys)
			if (unique.length == 0 || y - unique[unique.length - 1] > EPS)
				unique.push(y);
		ys.resize(0);
		for (y in unique)
			ys.push(y);
	}

	inline function top(e:Int):Float
		return Math.min(sy[e], ey[e]);

	inline function bottom(e:Int):Float
		return Math.max(sy[e], ey[e]);

	/** The edge's x at `y`, from its top end, so both bands either side of a point find it the same. **/
	inline function xAt(e:Int, y:Float):Float {
		var x0 = sy[e] < ey[e] ? sx[e] : ex[e], y0 = sy[e] < ey[e] ? sy[e] : ey[e];
		var x1 = sy[e] < ey[e] ? ex[e] : sx[e], y1 = sy[e] < ey[e] ? ey[e] : sy[e];
		return y <= y0 ? x0 : y >= y1 ? x1 : x0 + (x1 - x0) * (y - y0) / (y1 - y0);
	}

	/** +1 for an edge running down the page, -1 up: its share of the winding. **/
	inline function dir(e:Int):Int
		return ey[e] > sy[e] ? 1 : -1;

	inline function filled(w:Int):Bool
		return rule == EvenOdd ? w & 1 != 0 : w != 0;

	public function run(aa:Float, mesh:Mesh, c:Float):Void {
		// Level edges are in no band: whether the fill ends at one is found from the winding just above and below its middle.
		for (e in 0...sx.length)
			if (Math.abs(ey[e] - sy[e]) <= EPS && Math.abs(ex[e] - sx[e]) > EPS) {
				var mx = (sx[e] + ex[e]) / 2, my = sy[e], h = Math.max(1e-6, aa * 1e-3);
				var above = filled(winding(mx, my - h)), below = filled(winding(mx, my + h));
				if (above != below)
					levels.push([my, Math.min(sx[e], ex[e]), Math.max(sx[e], ex[e]), below ? 1 : -1, e]);
			}
		// Edges in order of their tops, added to the active set as the sweep reaches them.
		var order = [for (e in 0...sx.length) if (Math.abs(ey[e] - sy[e]) > EPS) e];
		order.sort((a, b) -> Reflect.compare(top(a), top(b)));
		var active:Array<Int> = [];
		var added = 0;
		var bandTop = ys[0];
		var at = 1;
		while (at < ys.length) {
			var bandBottom = ys[at];
			while (added < order.length && top(order[added]) <= bandTop + EPS)
				active.push(order[added++]);
			active = [for (e in active) if (bottom(e) > bandTop + EPS) e];
			var crossing = [for (e in active) if (top(e) <= bandTop + EPS && bottom(e) >= bandBottom - EPS) e];
			crossing.sort((a, b) -> {
				var d = xAt(a, bandTop) - xAt(b, bandTop);
				return Math.abs(d) > EPS ? (d < 0 ? -1 : 1) : Reflect.compare(xAt(a, bandBottom), xAt(b, bandBottom));
			});
			// Two edges that change places down the band cross in it: the band ends where the first pair does.
			for (k in 0...crossing.length - 1) {
				var a = crossing[k], b = crossing[k + 1];
				if (xAt(a, bandBottom) > xAt(b, bandBottom) + EPS) {
					var y = meet(a, b, bandTop, bandBottom);
					if (y > bandTop + EPS && y < bandBottom)
						bandBottom = y;
				}
			}
			band(crossing, bandTop, bandBottom, aa, mesh, c);
			bandTop = bandBottom;
			if (bandBottom >= ys[at] - EPS)
				at++;
		}
		fringes(aa, mesh, c);
	}

	/** Where edges `a` and `b`, which change places between `y0` and `y1`, cross. **/
	function meet(a:Int, b:Int, y0:Float, y1:Float):Float {
		var da0 = xAt(a, y0) - xAt(b, y0), da1 = xAt(a, y1) - xAt(b, y1);
		var t = da0 / (da0 - da1);
		return y0 + (y1 - y0) * Math.max(0, Math.min(1, t));
	}

	/**
		One band: the trapezoids where the winding is inside, and the pieces
		of edge where it changes from inside to out. A trapezoid's sides are
		the shape's edges, as it runs from where the fill starts to where it
		ends; its top or bottom is too where a level edge of the shape lies
		along it. Each vertex carries its distance inside each of those, in
		target pixels.
	**/
	function band(edges:Array<Int>, y0:Float, y1:Float, aa:Float, mesh:Mesh, c:Float):Void {
		var w = 0;
		var left = -1;
		for (e in edges) {
			var was = filled(w);
			w += dir(e);
			var now = filled(w);
			if (was == now)
				continue;
			pieces[e].push(y0);
			pieces[e].push(y1);
			pieces[e].push(now ? 1 : -1);
			if (now)
				left = e;
			else if (left >= 0) {
				var la = xAt(left, y0), lb = xAt(left, y1), ra = xAt(e, y0), rb = xAt(e, y1);
				if (ra - la > EPS || rb - lb > EPS)
					trapezoid(left, e, y0, y1, la, lb, ra, rb, aa, mesh, c);
				left = -1;
			}
		}
	}

	function trapezoid(l:Int, r:Int, y0:Float, y1:Float, la:Float, lb:Float, ra:Float, rb:Float, aa:Float, mesh:Mesh, c:Float):Void {
		// Inward normals of the side edges: rightward for the left side, leftward for the right.
		var ln = inward(l, 1), rn = inward(r, -1);
		var lx = xAt(l, y0), rx = xAt(r, y0);
		inline function dl(px:Float, py:Float)
			return ((px - lx) * ln[0] + (py - y0) * ln[1]) / aa;
		inline function dr(px:Float, py:Float)
			return ((px - rx) * rn[0] + (py - y0) * rn[1]) / aa;
		var top = alongLevel(y0, la, ra, 1), bottom = alongLevel(y1, lb, rb, -1);
		inline function dt(py:Float)
			return top ? (py - y0) / aa : Mesh.FAR;
		inline function db(py:Float)
			return bottom ? (y1 - py) / aa : Mesh.FAR;
		inline function v(px:Float, py:Float)
			mesh.vertex(px, py, c, dl(px, py), dr(px, py), dt(py), db(py));
		v(la, y0);
		v(ra, y0);
		v(rb, y1);
		v(la, y0);
		v(rb, y1);
		v(lb, y1);
	}

	/** The unit normal of edge `e` with an x of the sign of `side`. **/
	function inward(e:Int, side:Int):Array<Float> {
		var dx = ex[e] - sx[e], dy = ey[e] - sy[e];
		var l = Math.sqrt(dx * dx + dy * dy);
		var nx = dy / l, ny = -dx / l;
		return (nx > 0) == (side > 0) ? [nx, ny] : [-nx, -ny];
	}

	/** Whether a level edge of the fill lies along `y` over the span `x0` to `x1`, filled on the side `below` says. **/
	function alongLevel(y:Float, x0:Float, x1:Float, below:Int):Bool {
		for (l in levels)
			if (Math.abs(l[0] - y) <= EPS && l[3] == below && l[1] <= x0 + EPS && l[2] >= x1 - EPS)
				return true;
		return false;
	}

	/** How many times the contours wind round `(px, py)`. **/
	function winding(px:Float, py:Float):Int {
		var w = 0;
		for (e in 0...sx.length) {
			var ay = sy[e], by = ey[e];
			if (ay <= py) {
				if (by > py && (ex[e] - sx[e]) * (py - ay) - (px - sx[e]) * (by - ay) > 0)
					w++;
			} else if (by <= py && (ex[e] - sx[e]) * (py - ay) - (px - sx[e]) * (by - ay) < 0)
				w--;
		}
		return w;
	}

	/**
		The fringe along every piece of the fill's edge. A level edge is in
		no band: whether it is the fill's edge is found from the winding
		just above and below its middle. A piece's end at a corner, where
		the edge before or after is the fill's edge too, moves out to the
		corner's miter; anywhere else, square to its own edge.
	**/
	function fringes(aa:Float, mesh:Mesh, c:Float):Void {
		var count = sx.length;
		// Each edge's outward normal, and whether it is the fill's edge at its start and its end.
		var nx = [for (_ in 0...count) 0.0], ny = [for (_ in 0...count) 0.0];
		var atStart = [for (_ in 0...count) false], atEnd = [for (_ in 0...count) false];
		var lengths = [for (e in 0...count) Math.sqrt((ex[e] - sx[e]) * (ex[e] - sx[e]) + (ey[e] - sy[e]) * (ey[e] - sy[e]))];
		for (e in 0...count) {
			var l = lengths[e];
			if (l < EPS)
				continue;
			var dx = (ex[e] - sx[e]) / l, dy = (ey[e] - sy[e]) / l;
			if (Math.abs(ey[e] - sy[e]) <= EPS) {
				// Level: outward away from the side it is filled on, found before the bands.
				for (lv in levels)
					if (lv[4] == e) {
						nx[e] = 0;
						ny[e] = lv[3] > 0 ? -1 : 1;
						pieces[e] = [sy[e], sy[e], 0];
						atStart[e] = atEnd[e] = true;
					}
				continue;
			}
			var p = pieces[e];
			if (p.length == 0)
				continue;
			// Outward is away from the side it is filled on; sides are the same down the whole edge where nothing crosses it.
			var side = p[2];
			var rx = dy, ry = -dx;
			var pointsLeft = rx < 0;
			// Filled on the right of the page: outward points left.
			var outLeft = side > 0;
			nx[e] = pointsLeft == outLeft ? rx : -rx;
			ny[e] = pointsLeft == outLeft ? ry : -ry;
			var t = top(e), b = bottom(e);
			var touchesTop = false, touchesBottom = false;
			var i = 0;
			while (i < p.length) {
				if (Math.abs(p[i] - t) <= EPS)
					touchesTop = true;
				if (Math.abs(p[i + 1] - b) <= EPS)
					touchesBottom = true;
				i += 3;
			}
			var startIsTop = sy[e] < ey[e];
			atStart[e] = startIsTop ? touchesTop : touchesBottom;
			atEnd[e] = startIsTop ? touchesBottom : touchesTop;
		}
		function offset(e:Int, px:Float, py:Float):Array<Float> {
			// At the edge's start, joined to the edge before; at its end, to the edge after; anywhere else, its own normal.
			if (Math.abs(px - sx[e]) <= EPS && Math.abs(py - sy[e]) <= EPS && atEnd[prev[e]])
				return Tessellate.miter(nx[prev[e]], ny[prev[e]], nx[e], ny[e]);
			if (Math.abs(px - ex[e]) <= EPS && Math.abs(py - ey[e]) <= EPS && atStart[next[e]])
				return Tessellate.miter(nx[e], ny[e], nx[next[e]], ny[next[e]]);
			return [nx[e], ny[e]];
		}
		for (e in 0...count) {
			if (nx[e] == 0 && ny[e] == 0)
				continue;
			var p = pieces[e];
			if (Math.abs(ey[e] - sy[e]) <= EPS) {
				emit(e, sx[e], sy[e], ex[e], ey[e], offset, aa, mesh, c);
				continue;
			}
			// Pieces next to each other, from bands one after another, are one stretch of fringe.
			var spans:Array<Array<Float>> = [];
			var i = 0;
			while (i < p.length) {
				var last = spans.length > 0 ? spans[spans.length - 1] : null;
				if (last != null && Math.abs(last[1] - p[i]) <= EPS && last[2] == p[i + 2])
					last[1] = p[i + 1];
				else
					spans.push([p[i], p[i + 1], p[i + 2]]);
				i += 3;
			}
			for (sp in spans) {
				var ax = xAt(e, sp[0]), bx = xAt(e, sp[1]);
				// From the edge's start end toward its end, so the right corner is found.
				if (sy[e] < ey[e])
					emit(e, ax, sp[0], bx, sp[1], offset, aa, mesh, c);
				else
					emit(e, bx, sp[1], ax, sp[0], offset, aa, mesh, c);
			}
		}
	}

	/** A piece of the fringe: from half coverage at the edge to none half a pixel out, so a pixel is covered as much as it is inside the edge. **/
	inline function emit(e:Int, ax:Float, ay:Float, bx:Float, by:Float, offset:(Int, Float, Float) -> Array<Float>, aa:Float, mesh:Mesh,
			c:Float):Void {
		var oa = offset(e, ax, ay), ob = offset(e, bx, by);
		var w = aa * 0.5, h = c * 0.5;
		mesh.quad(ax, ay, h, bx, by, h, bx + ob[0] * w, by + ob[1] * w, 0, ax + oa[0] * w, ay + oa[1] * w, 0);
	}
}
