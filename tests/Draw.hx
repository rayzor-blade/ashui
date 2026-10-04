import ashui.draw.Affine;
import ashui.draw.Flatten;
import ashui.draw.Mesh;
import ashui.draw.Path;
import ashui.draw.Stroke;
import ashui.draw.Tessellate;

/** ashui.draw's vector core, without a GPU: flattening, and the triangles fills and strokes make. **/
class Draw {
	static var failures = 0;

	static function check(name:String, ok:Bool, ?detail:Dynamic) {
		if (!ok)
			failures++;
		Sys.println('${ok ? "ok  " : "FAIL"} $name${ok ? "" : ': $detail'}');
	}

	/** The mesh's area weighted by coverage: what it paints. **/
	static function painted(m:Mesh):Float {
		var sum = 0.0, d = m.data;
		var i = 0;
		while (i < d.length) {
			var area = Math.abs((d[i + 3] - d[i]) * (d[i + 7] - d[i + 1]) - (d[i + 6] - d[i]) * (d[i + 4] - d[i + 1])) / 2;
			sum += area * (d[i + 2] + d[i + 5] + d[i + 8]) / 3;
			i += 9;
		}
		return sum;
	}

	/** The area of the triangles at full coverage only. **/
	static function solid(m:Mesh):Float {
		var sum = 0.0, d = m.data;
		var i = 0;
		while (i < d.length) {
			if (d[i + 2] == 1 && d[i + 5] == 1 && d[i + 8] == 1)
				sum += Math.abs((d[i + 3] - d[i]) * (d[i + 7] - d[i + 1]) - (d[i + 6] - d[i]) * (d[i + 4] - d[i + 1])) / 2;
			i += 9;
		}
		return sum;
	}

	static function finite(m:Mesh):Bool {
		for (v in m.data)
			if (Math.isNaN(v) || !Math.isFinite(v))
				return false;
		return true;
	}

	static function fill(p:Path, ?rule:FillRule, aa = 1.0):Mesh {
		var m = new Mesh();
		Tessellate.fill(Flatten.path(p, Affine.IDENTITY, 0.25), rule == null ? NonZero : rule, aa, m);
		return m;
	}

	static function stroke(p:Path, s:Stroke, aa = 1.0):Mesh {
		var m = new Mesh();
		Tessellate.stroke(Flatten.path(p, Affine.IDENTITY, 0.25), s, 1, aa, m);
		return m;
	}

	static function main() {
		// --- Flattening ---
		var circle = Flatten.path(new Path().circle(0, 0, 100), Affine.IDENTITY, 0.25);
		var worst = 0.0;
		for (i in 0...circle[0].count())
			worst = Math.max(worst, Math.abs(Math.sqrt(circle[0].x(i) * circle[0].x(i) + circle[0].y(i) * circle[0].y(i)) - 100));
		check("a circle flattens closed, its points on it, in no more steps than it needs", circle.length == 1 && circle[0].closed && worst < 0.05
			&& circle[0].count() >= 16 && circle[0].count() <= 128, [circle[0].count(), worst]);
		var bigger = Flatten.path(new Path().circle(0, 0, 100), Affine.scaling(4, 4), 0.25);
		check("drawn larger, a curve gets more steps", bigger[0].count() > circle[0].count(), [circle[0].count(), bigger[0].count()]);
		var arc = Flatten.path(new Path().moveTo(0, 0).arcTo(50, 50, 0, false, true, 100, 0), Affine.IDENTITY, 0.1);
		var mid = arc[0].y(arc[0].count() >> 1);
		check("an arc's sweep flag picks its side: clockwise on screen bulges up", mid < -40 && !arc[0].closed, mid);
		var moved = Flatten.path(new Path().rect(0, 0, 10, 10), Affine.translation(5, 7).after(Affine.scaling(2, 2)), 0.25);
		check("points go through the transform", moved[0].x(2) == 25 && moved[0].y(2) == 27, [moved[0].x(2), moved[0].y(2)]);

		// --- Fills ---
		var square = fill(new Path().rect(0, 0, 10, 10));
		check("a square fills its area, and its fringe a pixel wide around it", Math.abs(solid(square) - 100) < 1e-6
			&& Math.abs(painted(square) - 100 - 40 * 0.5) < 2, [solid(square), painted(square)]);
		var l = fill(new Path().moveTo(0, 0).lineTo(20, 0).lineTo(20, 5).lineTo(5, 5).lineTo(5, 20).lineTo(0, 20).close());
		check("a concave shape fills its area exactly, no triangle over another", Math.abs(solid(l) - 175) < 1e-6, solid(l));
		var framed = new Path().rect(0, 0, 10, 10).rect(2, 2, 6, 6);
		var evenOdd = fill(framed, EvenOdd);
		check("even-odd cuts a hole of a path inside another", Math.abs(solid(evenOdd) - 64) < 1e-6, solid(evenOdd));
		var sameWay = fill(framed, NonZero);
		check("non-zero fills a path inside another running the same way", Math.abs(solid(sameWay) - 100) < 1e-6, solid(sameWay));
		var reversed = fill(new Path().rect(0, 0, 10, 10).moveTo(2, 2).lineTo(2, 8).lineTo(8, 8).lineTo(8, 2).close(), NonZero);
		check("non-zero cuts a hole of a path running the other way", Math.abs(solid(reversed) - 64) < 1e-6, solid(reversed));
		var twoHoles = fill(new Path().rect(0, 0, 30, 10).rect(2, 2, 6, 6).rect(20, 2, 6, 6), EvenOdd);
		check("several holes in one shape", Math.abs(solid(twoHoles) - (300 - 72)) < 1e-6, solid(twoHoles));
		var apart = fill(new Path().rect(0, 0, 10, 10).rect(20, 0, 5, 5));
		check("shapes apart fill each", Math.abs(solid(apart) - 125) < 1e-6, solid(apart));
		var discPath = new Path().circle(50, 50, 40);
		var disc = fill(discPath);
		var flatArea = Math.abs(Flatten.path(discPath, Affine.IDENTITY, 0.25)[0].area2()) / 2;
		check("a disc fills the area of its steps exactly, close to the circle's", Math.abs(solid(disc) - flatArea) < 1e-6
			&& Math.abs(flatArea - Math.PI * 1600) < 50 && finite(disc), [solid(disc), flatArea]);
		var bowtie = new Path().moveTo(0, 0).lineTo(10, 10).lineTo(10, 0).lineTo(0, 10).close();
		var crossed = fill(bowtie);
		check("a path crossing itself fills both its lobes, nothing over another", Math.abs(solid(crossed) - 50) < 1e-6 && finite(crossed), solid(crossed));
		var overlap = fill(new Path().rect(0, 0, 10, 10).rect(5, 5, 10, 10));
		check("overlapping paths fill their union once, by non-zero", Math.abs(solid(overlap) - 175) < 1e-6, solid(overlap));
		check("a concave shape's fringe runs its whole outline, half its length at full weight", Math.abs(painted(l) - 175 - 80 * 0.5) < 3, painted(l));
		check("overlapping paths have a fringe on their union's outline alone, none where they cross inside",
			Math.abs(painted(overlap) - 175 - 60 * 0.5) < 3, painted(overlap));
		var star = new Path().moveTo(50, 0).lineTo(79, 90).lineTo(2, 34).lineTo(98, 34).lineTo(21, 90).close();
		var starNonZero = solid(fill(star, NonZero)), starEvenOdd = solid(fill(star, EvenOdd));
		check("a star is filled whole by non-zero, its middle left out by even-odd", starNonZero > starEvenOdd + 500 && starEvenOdd > 1000,
			[starNonZero, starEvenOdd]);

		// --- Strokes ---
		var line = stroke(new Path().moveTo(0, 0).lineTo(100, 0), new Stroke(4));
		check("a line paints its length by its width, its butt ends fading over a pixel", Math.abs(painted(line) - 4 * 101) < 1.5 && finite(line),
			painted(line));
		var squareCap = stroke(new Path().moveTo(0, 0).lineTo(100, 0), new Stroke(4, Square));
		check("square caps add half the width at each end", Math.abs(painted(squareCap) - 4 * 105) < 1.5, painted(squareCap));
		var roundCap = stroke(new Path().moveTo(0, 0).lineTo(100, 0), new Stroke(4, Round));
		check("round caps add a disc between them", Math.abs(painted(roundCap) - (400 + Math.PI * 4)) < 2, painted(roundCap));
		var hair = stroke(new Path().moveTo(0, 0).lineTo(100, 0), new Stroke(0.25));
		check("a hairline keeps its weight, drawn a pixel wide and fainter", Math.abs(painted(hair) - 0.25 * 101) < 0.5, painted(hair));
		var corner = stroke(new Path().moveTo(0, 0).lineTo(100, 0).lineTo(100, 100), new Stroke(10, Butt, Miter));
		var bevel = stroke(new Path().moveTo(0, 0).lineTo(100, 0).lineTo(100, 100), new Stroke(10, Butt, Bevel));
		var roundJoin = stroke(new Path().moveTo(0, 0).lineTo(100, 0).lineTo(100, 100), new Stroke(10, Butt, Round));
		check("a miter fills the corner's square, a round join less, a bevel half",
			painted(corner) > painted(roundJoin) && painted(roundJoin) > painted(bevel) && Math.abs(painted(corner) - painted(bevel) - 12.5) < 2
			&& finite(corner) && finite(roundJoin), [painted(corner), painted(roundJoin), painted(bevel)]);
		var sharp = stroke(new Path().moveTo(0, 0).lineTo(100, 0).lineTo(0, 5), new Stroke(10, Butt, Miter, 4));
		check("past the miter limit, a sharp corner is cut across", finite(sharp) && painted(sharp) < 10 * 205, painted(sharp));
		var box = stroke(new Path().rect(0, 0, 50, 50), new Stroke(2));
		check("a closed path's band goes all the way round, joined at its start", Math.abs(painted(box) - 2 * 200) < 6 && finite(box), painted(box));
		var dashes = stroke(new Path().moveTo(0, 0).lineTo(100, 0), new Stroke(2, Butt, Miter, 4, [10, 10]));
		check("dashes paint their share of the line", Math.abs(painted(dashes) - 2 * (50 + 5)) < 2, painted(dashes));
		var dot = stroke(new Path().moveTo(10, 10).lineTo(10, 10), new Stroke(6, Round));
		check("a point with round caps is a dot", Math.abs(painted(dot) - Math.PI * 9) < 2, painted(dot));
		var curve = stroke(new Path().moveTo(0, 0).cubicTo(30, -40, 70, 40, 100, 0), new Stroke(3, Butt, Round));
		check("a curve's band has nothing undefined", finite(curve) && painted(curve) > 3 * 100, painted(curve));

		Sys.println(failures == 0 ? "ALL PASSED" : '$failures FAILED');
		Sys.exit(failures == 0 ? 0 : 1);
	}
}
