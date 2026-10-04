package ashui.draw;

import ashui.draw.Flatten.Contour;
import ashui.draw.Path.FillRule;

/**
	A fill cut into trapezoids by a sweep down the page (see
	`Tessellate.fill`), and the fringe along the pieces of edge where it
	ends. Edges are kept as the contours run, each with where it starts
	and ends, so corners between edges of the fill's edge get a miter.

	One sweep is kept and reused, its arrays cleared rather than made
	again, as a canvas fills shapes every frame it draws.
**/
@:allow(ashui.draw)
class Sweep {
	static inline var EPS = 1e-9;

	static final shared = new Sweep();

	var rule:FillRule = NonZero;

	/** Each edge from its start to its end, as its contour runs. **/
	final sx:Array<Float> = [];

	final sy:Array<Float> = [];
	final ex:Array<Float> = [];
	final ey:Array<Float> = [];

	/** The edges before and after each in its contour. **/
	final prev:Array<Int> = [];

	final next:Array<Int> = [];

	/**
		Where each edge is the fill's edge, as pieces in a list per edge, in
		the order the bands met them: a piece's top and bottom y, the side
		it is filled on (1 right on the page, -1 left), and the next piece
		of its edge, -1 for none.
	**/
	final pieceTop:Array<Float> = [];

	final pieceBottom:Array<Float> = [];
	final pieceSide:Array<Int> = [];
	final pieceNext:Array<Int> = [];
	final firstPiece:Array<Int> = [];
	final lastPiece:Array<Int> = [];

	/** The vertex ys, sorted, each once. **/
	final ys:Array<Float> = [];

	/** Level edges where the fill ends: the edge, and 1 where it is filled below, -1 above. **/
	final levelEdge:Array<Int> = [];

	final levelBelow:Array<Int> = [];

	/** Edges by their tops; those the sweep is in; those crossing the band it is at, in order across it. **/
	final order:Array<Int> = [];

	final active:Array<Int> = [];
	final crossing:Array<Int> = [];

	/** Per edge, for its fringe: its outward normal, and whether it is the fill's edge at its start and its end. **/
	final nx:Array<Float> = [];

	final ny:Array<Float> = [];
	final atStart:Array<Bool> = [];
	final atEnd:Array<Bool> = [];

	/** Where `offset`, `inward` and `miter` leave what they find. **/
	var ox = 0.0;

	var oy = 0.0;

	function new() {}

	/** The fill of `rings` by `rule` into `mesh`. **/
	public static function fill(rings:Array<Contour>, rule:FillRule, aa:Float, mesh:Mesh, c:Float):Void {
		var s = shared;
		s.reset(rings, rule);
		s.run(aa, mesh, c);
	}

	function reset(rings:Array<Contour>, rule:FillRule):Void {
		this.rule = rule;
		sx.resize(0);
		sy.resize(0);
		ex.resize(0);
		ey.resize(0);
		pieceTop.resize(0);
		pieceBottom.resize(0);
		ys.resize(0);
		prev.resize(0);
		next.resize(0);
		pieceSide.resize(0);
		pieceNext.resize(0);
		firstPiece.resize(0);
		lastPiece.resize(0);
		levelEdge.resize(0);
		levelBelow.resize(0);
		order.resize(0);
		active.resize(0);
		crossing.resize(0);
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
				firstPiece.push(-1);
				lastPiece.push(-1);
				ys.push(r.y(i));
			}
		}
		sortFloats(ys);
		// Each y once.
		var k = 0;
		for (i in 0...ys.length)
			if (k == 0 || ys[i] - ys[k - 1] > EPS)
				ys[k++] = ys[i];
		ys.resize(k);
	}

	/** Sorted in place, smallest first. **/
	static function sortFloats(a:Array<Float>):Void {
		// Shell sort: no closure, no copy, and quick on the few hundred ys a shape has.
		var gap = a.length >> 1;
		while (gap > 0) {
			for (i in gap...a.length) {
				var v = a[i], j = i;
				while (j >= gap && a[j - gap] > v) {
					a[j] = a[j - gap];
					j -= gap;
				}
				a[j] = v;
			}
			gap >>= 1;
		}
	}

	inline function top(e:Int):Float
		return sy[e] < ey[e] ? sy[e] : ey[e];

	inline function bottom(e:Int):Float
		return sy[e] > ey[e] ? sy[e] : ey[e];

	/** The edge's x at `y`, from its top end, so both bands either side of a point find it the same. **/
	inline function xAt(e:Int, y:Float):Float {
		var down = sy[e] < ey[e];
		var x0 = down ? sx[e] : ex[e], y0 = down ? sy[e] : ey[e];
		var x1 = down ? ex[e] : sx[e], y1 = down ? ey[e] : sy[e];
		return y <= y0 ? x0 : y >= y1 ? x1 : x0 + (x1 - x0) * (y - y0) / (y1 - y0);
	}

	/** +1 for an edge running down the page, -1 up: its share of the winding. **/
	inline function dir(e:Int):Int
		return ey[e] > sy[e] ? 1 : -1;

	inline function filled(w:Int):Bool
		return rule == EvenOdd ? w & 1 != 0 : w != 0;

	function run(aa:Float, mesh:Mesh, c:Float):Void {
		if (ys.length == 0)
			return;
		// Level edges are in no band: whether the fill ends at one is found from the winding just above and below its middle.
		for (e in 0...sx.length)
			if (Math.abs(ey[e] - sy[e]) <= EPS && Math.abs(ex[e] - sx[e]) > EPS) {
				var mx = (sx[e] + ex[e]) / 2, my = sy[e], h = Math.max(1e-6, aa * 1e-3);
				var above = filled(winding(mx, my - h)), below = filled(winding(mx, my + h));
				if (above != below) {
					levelEdge.push(e);
					levelBelow.push(below ? 1 : -1);
				}
			}
		// Edges in order of their tops, added to the active set as the sweep reaches them.
		for (e in 0...sx.length)
			if (Math.abs(ey[e] - sy[e]) > EPS) {
				var t = top(e), j = order.length - 1;
				order.push(e);
				while (j >= 0 && top(order[j]) > t) {
					order[j + 1] = order[j];
					j--;
				}
				order[j + 1] = e;
			}
		var added = 0;
		var bandTop = ys[0];
		var at = 1;
		while (at < ys.length) {
			var bandBottom = ys[at];
			while (added < order.length && top(order[added]) <= bandTop + EPS)
				active.push(order[added++]);
			// Edges ended above the band leave the active set; those through it cross it.
			var k = 0;
			crossing.resize(0);
			for (i in 0...active.length) {
				var e = active[i];
				if (bottom(e) <= bandTop + EPS)
					continue;
				active[k++] = e;
				if (top(e) <= bandTop + EPS && bottom(e) >= bandBottom - EPS)
					crossing.push(e);
			}
			active.resize(k);
			sortAcross(bandTop, bandBottom);
			// Two edges that change places down the band cross in it: the band ends where the first pair does.
			for (k in 0...crossing.length - 1) {
				var a = crossing[k], b = crossing[k + 1];
				if (xAt(a, bandBottom) > xAt(b, bandBottom) + EPS) {
					var y = meet(a, b, bandTop, bandBottom);
					if (y > bandTop + EPS && y < bandBottom)
						bandBottom = y;
				}
			}
			band(bandTop, bandBottom, aa, mesh, c);
			bandTop = bandBottom;
			if (bandBottom >= ys[at] - EPS)
				at++;
		}
		fringes(aa, mesh, c);
	}

	/** The crossing edges in order across the band's top, ties by its bottom: insertion sort, the order much as the last band's. **/
	function sortAcross(y0:Float, y1:Float):Void {
		for (i in 1...crossing.length) {
			var e = crossing[i], x0 = xAt(e, y0), x1 = xAt(e, y1);
			var j = i - 1;
			while (j >= 0) {
				var f = crossing[j], d = xAt(f, y0) - x0;
				if (d < -EPS || (Math.abs(d) <= EPS && xAt(f, y1) <= x1))
					break;
				crossing[j + 1] = f;
				j--;
			}
			crossing[j + 1] = e;
		}
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
	function band(y0:Float, y1:Float, aa:Float, mesh:Mesh, c:Float):Void {
		var w = 0;
		var left = -1;
		for (e in crossing) {
			var was = filled(w);
			w += dir(e);
			var now = filled(w);
			if (was == now)
				continue;
			addPiece(e, y0, y1, now ? 1 : -1);
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

	/** A piece of edge `e`, joined to its last piece when it carries on from it on the same side. **/
	function addPiece(e:Int, y0:Float, y1:Float, side:Int):Void {
		var last = lastPiece[e];
		if (last >= 0 && Math.abs(pieceBottom[last] - y0) <= EPS && pieceSide[last] == side) {
			pieceBottom[last] = y1;
			return;
		}
		var p = pieceTop.length;
		pieceTop.push(y0);
		pieceBottom.push(y1);
		pieceSide.push(side);
		pieceNext.push(-1);
		if (last >= 0)
			pieceNext[last] = p;
		else
			firstPiece[e] = p;
		lastPiece[e] = p;
	}

	function trapezoid(l:Int, r:Int, y0:Float, y1:Float, la:Float, lb:Float, ra:Float, rb:Float, aa:Float, mesh:Mesh, c:Float):Void {
		// Inward normals of the side edges: rightward for the left side, leftward for the right.
		inward(l, 1);
		var lnx = ox, lny = oy;
		inward(r, -1);
		var rnx = ox, rny = oy;
		var lx = xAt(l, y0), rx = xAt(r, y0);
		var top = alongLevel(y0, la, ra, 1), bottom = alongLevel(y1, lb, rb, -1);
		inline function v(px:Float, py:Float)
			mesh.vertex(px, py, c, ((px - lx) * lnx + (py - y0) * lny) / aa, ((px - rx) * rnx + (py - y0) * rny) / aa,
				top ? (py - y0) / aa : Mesh.FAR, bottom ? (y1 - py) / aa : Mesh.FAR);
		v(la, y0);
		v(ra, y0);
		v(rb, y1);
		v(la, y0);
		v(rb, y1);
		v(lb, y1);
	}

	/** The unit normal of edge `e` with an x of the sign of `side`, into `ox, oy`. **/
	function inward(e:Int, side:Int):Void {
		var dx = ex[e] - sx[e], dy = ey[e] - sy[e];
		var l = Math.sqrt(dx * dx + dy * dy);
		var nx = dy / l, ny = -dx / l;
		var flip = (nx > 0) != (side > 0);
		ox = flip ? -nx : nx;
		oy = flip ? -ny : ny;
	}

	/** Whether a level edge of the fill lies along `y` over the span `x0` to `x1`, filled on the side `below` says. **/
	function alongLevel(y:Float, x0:Float, x1:Float, below:Int):Bool {
		for (i in 0...levelEdge.length) {
			var e = levelEdge[i];
			if (levelBelow[i] == below && Math.abs(sy[e] - y) <= EPS && Math.min(sx[e], ex[e]) <= x0 + EPS && Math.max(sx[e], ex[e]) >= x1 - EPS)
				return true;
		}
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
		The fringe along every piece of the fill's edge. A level edge is the
		fill's edge whole, as found before the bands. A piece's end at a
		corner, where the edge before or after is the fill's edge too, moves
		out to the corner's miter; anywhere else, square to its own edge.
	**/
	function fringes(aa:Float, mesh:Mesh, c:Float):Void {
		var count = sx.length;
		nx.resize(0);
		ny.resize(0);
		atStart.resize(0);
		atEnd.resize(0);
		for (e in 0...count) {
			nx.push(0);
			ny.push(0);
			atStart.push(false);
			atEnd.push(false);
		}
		for (i in 0...levelEdge.length) {
			var e = levelEdge[i];
			// Outward, away from the side it is filled on.
			ny[e] = levelBelow[i] > 0 ? -1 : 1;
			atStart[e] = atEnd[e] = true;
		}
		for (e in 0...count) {
			var p = firstPiece[e];
			if (p < 0)
				continue;
			var dx = ex[e] - sx[e], dy = ey[e] - sy[e];
			var l = Math.sqrt(dx * dx + dy * dy);
			if (l < EPS)
				continue;
			// Filled on the right of the page: outward points left. The side is the same down the whole edge where nothing crosses it.
			var rx = dy / l, ry = -dx / l;
			var flip = (rx < 0) != (pieceSide[p] > 0);
			nx[e] = flip ? -rx : rx;
			ny[e] = flip ? -ry : ry;
			var t = top(e), b = bottom(e);
			var touchesTop = false, touchesBottom = false;
			while (p >= 0) {
				if (Math.abs(pieceTop[p] - t) <= EPS)
					touchesTop = true;
				if (Math.abs(pieceBottom[p] - b) <= EPS)
					touchesBottom = true;
				p = pieceNext[p];
			}
			var startIsTop = sy[e] < ey[e];
			atStart[e] = startIsTop ? touchesTop : touchesBottom;
			atEnd[e] = startIsTop ? touchesBottom : touchesTop;
		}
		for (e in 0...count) {
			if (nx[e] == 0 && ny[e] == 0)
				continue;
			if (Math.abs(ey[e] - sy[e]) <= EPS) {
				emit(e, sx[e], sy[e], ex[e], ey[e], aa, mesh, c);
				continue;
			}
			var p = firstPiece[e];
			while (p >= 0) {
				var y0 = pieceTop[p], y1 = pieceBottom[p];
				// From the edge's start end toward its end, so the right corner is found.
				if (sy[e] < ey[e])
					emit(e, xAt(e, y0), y0, xAt(e, y1), y1, aa, mesh, c);
				else
					emit(e, xAt(e, y1), y1, xAt(e, y0), y0, aa, mesh, c);
				p = pieceNext[p];
			}
		}
	}

	/** Where a piece of edge `e` ending at `(px, py)` moves out to, into `ox, oy`: at its corners joined to the edges either side, else its own normal. **/
	function offset(e:Int, px:Float, py:Float):Void {
		if (Math.abs(px - sx[e]) <= EPS && Math.abs(py - sy[e]) <= EPS && atEnd[prev[e]])
			miter(nx[prev[e]], ny[prev[e]], nx[e], ny[e]);
		else if (Math.abs(px - ex[e]) <= EPS && Math.abs(py - ey[e]) <= EPS && atStart[next[e]])
			miter(nx[e], ny[e], nx[next[e]], ny[next[e]]);
		else {
			ox = nx[e];
			oy = ny[e];
		}
	}

	/** Where a corner between edges of outward normals `a` and `b` moves out to, for the strip to keep its width: a little at most. **/
	function miter(ax:Float, ay:Float, bx:Float, by:Float):Void {
		var mx = ax + bx, my = ay + by;
		var ml = Math.sqrt(mx * mx + my * my);
		if (ml < 1e-9) {
			ox = ax;
			oy = ay;
			return;
		}
		mx /= ml;
		my /= ml;
		var k = 1 / Math.max(mx * ax + my * ay, 0.25);
		ox = mx * k;
		oy = my * k;
	}

	/** A piece of the fringe: from half coverage at the edge to none half a pixel out, so a pixel is covered as much as it is inside the edge. **/
	function emit(e:Int, ax:Float, ay:Float, bx:Float, by:Float, aa:Float, mesh:Mesh, c:Float):Void {
		var w = aa * 0.5, h = c * 0.5;
		offset(e, ax, ay);
		var oax = ax + ox * w, oay = ay + oy * w;
		offset(e, bx, by);
		var obx = bx + ox * w, oby = by + oy * w;
		mesh.quad(ax, ay, h, bx, by, h, obx, oby, 0, oax, oay, 0);
	}
}
