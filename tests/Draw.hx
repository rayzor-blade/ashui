import ashui.draw.Affine;
import ashui.draw.Flatten;
import ashui.draw.Mesh;
import ashui.draw.Path;
import ashui.draw.Stroke;
import ashui.draw.Tessellate;
import ashui.math.Mat4;
import ashui.math.Quat;
import ashui.math.Vec3;

/** ashui.draw's vector core, without a GPU: flattening, and the triangles fills and strokes make. **/
class Draw {
	static var failures = 0;

	static function check(name:String, ok:Bool, ?detail:Dynamic) {
		if (!ok)
			failures++;
		Sys.println('${ok ? "ok  " : "FAIL"} $name${ok ? "" : ': $detail'}');
	}

	static inline var S = Mesh.STRIDE;

	/** A triangle's area, its first vertex at `i`. **/
	static function area(d:Array<Float>, i:Int):Float
		return Math.abs((d[i + S] - d[i]) * (d[i + 2 * S + 1] - d[i + 1]) - (d[i + 2 * S] - d[i]) * (d[i + S + 1] - d[i + 1])) / 2;

	/** The mesh's area weighted by coverage: what it paints, its distances aside. **/
	static function painted(m:Mesh):Float {
		var sum = 0.0, d = m.data;
		var i = 0;
		while (i < d.length) {
			sum += area(d, i) * (d[i + 2] + d[i + S + 2] + d[i + 2 * S + 2]) / 3;
			i += 3 * S;
		}
		return sum;
	}

	/** The area of the triangles at full coverage only. **/
	static function solid(m:Mesh):Float {
		var sum = 0.0, d = m.data;
		var i = 0;
		while (i < d.length) {
			if (d[i + 2] == 1 && d[i + S + 2] == 1 && d[i + 2 * S + 2] == 1)
				sum += area(d, i);
			i += 3 * S;
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
		check("a square fills its area, and its fringe half a pixel out from half weight", Math.abs(solid(square) - 100) < 1e-6
			&& Math.abs(painted(square) - 100 - 40 * 0.125) < 1, [solid(square), painted(square)]);
		// A square's trapezoid: each vertex as far inside each side as it is, in pixels; its corner on two sides at once.
		var corner = square.data.slice(0, S);
		var far = [for (i in 0...Std.int(square.data.length / S)) square.data[i * S + 2] == 1 ? Math.max(square.data[i * S + 3], square.data[i * S + 4]) : 0];
		check("a fill's vertices carry their distance inside its edges, in pixels", corner[0] == 0 && corner[1] == 0 && corner[3] == 0
			&& corner[5] == 0 && far.indexOf(10) >= 0, corner);
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
		check("a concave shape's fringe runs its whole outline", Math.abs(painted(l) - 175 - 80 * 0.125) < 1.5, painted(l));
		check("overlapping paths have a fringe on their union's outline alone, none where they cross inside",
			Math.abs(painted(overlap) - 175 - 60 * 0.125) < 1.5, painted(overlap));
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

		// --- 3D math ---
		inline function near(a:Vec3, b:Vec3)
			return a.distance(b) < 1e-9;
		var quarter = Quat.axisAngle(Vec3.UP, Math.PI / 2);
		check("a quarter turn about Y takes +X to -Z", near(quarter.rotate(new Vec3(1, 0, 0)), new Vec3(0, 0, -1)), quarter.rotate(new Vec3(1, 0, 0)));
		check("its matrix turns points as it does", near(Mat4.rotation(quarter).transformPoint(new Vec3(1, 2, 3)), quarter.rotate(new Vec3(1, 2, 3))));
		var node = Mat4.compose(new Vec3(1, 2, 3), Quat.euler(0.3, -0.7, 1.1), new Vec3(2, 0.5, 3));
		var undone = node.inverse();
		check("a node's transform and its inverse undo each other", undone != null && near(undone.transformPoint(node.transformPoint(new Vec3(4, -5, 6))), new Vec3(4, -5, 6)));
		check("compose scales, then turns, then moves", near(node.transformPoint(Vec3.ZERO), new Vec3(1, 2, 3))
			&& near(node.transformDirection(new Vec3(1, 0, 0)), Quat.euler(0.3, -0.7, 1.1).rotate(new Vec3(2, 0, 0))));
		var a = Mat4.translation(new Vec3(5, 0, 0)), b = Mat4.scaling(new Vec3(2, 2, 2));
		check("a.mul(b) applies b first", near(a.mul(b).transformPoint(new Vec3(1, 1, 1)), new Vec3(7, 2, 2)));
		var view = Mat4.lookAt(new Vec3(0, 0, 5), Vec3.ZERO, Vec3.UP);
		check("a camera at +Z looking at the origin sees it 5 ahead, down -Z", near(view.transformPoint(Vec3.ZERO), new Vec3(0, 0, -5)));
		check("and keeps +Y up", near(view.transformDirection(Vec3.UP), Vec3.UP));
		var proj = Mat4.perspective(Math.PI / 2, 2, 0.1, 100);
		check("the near plane projects to depth 0, the far to 1", Math.abs(proj.transformPoint(new Vec3(0, 0, -0.1)).z) < 1e-9
			&& Math.abs(proj.transformPoint(new Vec3(0, 0, -100)).z - 1) < 1e-9);
		check("a 90° view reaches the top edge at 45°, the side at 45° times the aspect", Math.abs(proj.transformPoint(new Vec3(0, 1, -1)).y - 1) < 1e-9
			&& Math.abs(proj.transformPoint(new Vec3(2, 0, -1)).x - 1) < 1e-9);
		var squash = Mat4.scaling(new Vec3(1, 4, 1));
		var n = squash.normalMatrix().transformDirection(new Vec3(1, 1, 0).normalize()).normalize();
		var surface = squash.transformDirection(new Vec3(1, -1, 0));
		check("normals stay perpendicular to a surface squashed unevenly", Math.abs(n.dot(surface)) < 1e-9, n);
		var halfway = Quat.IDENTITY.slerp(quarter, 0.5);
		check("slerp halfway through a quarter turn is an eighth", near(halfway.rotate(new Vec3(1, 0, 0)), new Vec3(Math.cos(Math.PI / 4), 0, -Math.sin(Math.PI / 4))));

		// --- Block compression ---
		var Bc = ashui.draw3d.BcEncoder;
		// A smooth, varied 64×64 image: colour ramps one way, a darker band the other, alpha a ramp.
		var iw = 64, ih = 64;
		var img = haxe.io.Bytes.alloc(iw * ih * 4);
		for (y in 0...ih)
			for (x in 0...iw) {
				var p = (y * iw + x) * 4;
				img.set(p, x * 4);
				img.set(p + 1, 255 - y * 3);
				img.set(p + 2, Std.int(128 + 100 * Math.sin((x + y) * 0.1)));
				img.set(p + 3, 255 - x);
			}
		var bc1 = Bc.bc1(img, iw, ih), bc4 = Bc.bc4(img, iw, ih, 2), bc5 = Bc.bc5(img, iw, ih), bc3 = Bc.bc3(img, iw, ih);
		check("block sizes: BC1 and BC4 8 bytes a block, BC3 and BC5 16", bc1.length == 256 * 8 && bc4.length == 256 * 8 && bc5.length == 256 * 16
			&& bc3.length == 256 * 16);
		check("BC1 keeps a smooth image within about 35dB", BcCheck.psnr1(img, iw, ih, bc1, 0, 8) > 34, BcCheck.psnr1(img, iw, ih, bc1, 0, 8));
		check("BC4 keeps a channel within about 43dB", BcCheck.psnr4(img, iw, ih, bc4, 0, 8, 2) > 42, BcCheck.psnr4(img, iw, ih, bc4, 0, 8, 2));
		check("BC5 is red then green, each as BC4", BcCheck.psnr4(img, iw, ih, bc5, 0, 16, 0) > 42 && BcCheck.psnr4(img, iw, ih, bc5, 8, 16, 1) > 42);
		check("BC3 is alpha as BC4, then colour as BC1", BcCheck.psnr4(img, iw, ih, bc3, 0, 16, 3) > 42 && BcCheck.psnr1(img, iw, ih, bc3, 8, 16) > 34);
		check("an image with any alpha short of full is not opaque, one without is", !Bc.opaque(img) && Bc.opaque(haxe.io.Bytes.ofHex("ff0000ff00ff00ff")));
		// Eight levels exactly between two values come back exactly.
		var steps = haxe.io.Bytes.alloc(16 * 4);
		for (i in 0...16)
			steps.set(i * 4, 100 + [0, 10, 20, 30, 40, 50, 60, 70][i % 8]);
		check("BC4 gives back each of eight even steps exactly", BcCheck.psnr4(steps, 4, 4, Bc.bc4(steps, 4, 4), 0, 8, 0) == Math.POSITIVE_INFINITY);
		var odd = Bc.bc1(img.sub(0, 6 * 5 * 4), 6, 5);
		check("sides not a multiple of 4 fill their blocks", odd.length == 4 * 8);

		Sys.println(failures == 0 ? "ALL PASSED" : '$failures FAILED');
		Sys.exit(failures == 0 ? 0 : 1);
	}
}

/** Decodes BC blocks as the format describes, to measure how close an encoder kept an image. **/
class BcCheck {
	/** PSNR of a BC1 colour block at `offset` in each `stride`-byte block of `bc`, against `img`'s red, green and blue. **/
	public static function psnr1(img:haxe.io.Bytes, w:Int, h:Int, bc:haxe.io.Bytes, offset:Int, stride:Int):Float {
		var err = 0.0, n = 0, o = offset;
		for (by in 0...(h + 3) >> 2)
			for (bx in 0...(w + 3) >> 2) {
				var c0 = bc.getUInt16(o), c1 = bc.getUInt16(o + 2), idx = bc.getInt32(o + 4);
				var e0 = [(c0 >> 11) << 3 | (c0 >> 13), ((c0 >> 5) & 63) << 2 | ((c0 >> 9) & 3), (c0 & 31) << 3 | ((c0 & 31) >> 2)];
				var e1 = [(c1 >> 11) << 3 | (c1 >> 13), ((c1 >> 5) & 63) << 2 | ((c1 >> 9) & 3), (c1 & 31) << 3 | ((c1 & 31) >> 2)];
				var pal = [e0, e1, [for (c in 0...3) Std.int((2 * e0[c] + e1[c]) / 3)], [for (c in 0...3) Std.int((e0[c] + 2 * e1[c]) / 3)]];
				if (c0 <= c1)
					pal = [e0, e1, [for (c in 0...3) (e0[c] + e1[c]) >> 1], [0, 0, 0]];
				for (i in 0...16) {
					var x = (bx << 2) + (i & 3), y = (by << 2) + (i >> 2);
					if (x >= w || y >= h)
						continue;
					var q = pal[(idx >>> (i * 2)) & 3];
					for (c in 0...3) {
						var d = img.get((y * w + x) * 4 + c) - q[c];
						err += d * d;
						n++;
					}
				}
				o += stride;
			}
		return err == 0 ? Math.POSITIVE_INFINITY : 10 * Math.log(255 * 255 / (err / n)) / Math.log(10);
	}

	/** PSNR of a BC4 block at `offset` in each `stride`-byte block of `bc`, against `img`'s channel `channel`. **/
	public static function psnr4(img:haxe.io.Bytes, w:Int, h:Int, bc:haxe.io.Bytes, offset:Int, stride:Int, channel:Int):Float {
		var err = 0.0, n = 0, o = offset;
		for (by in 0...(h + 3) >> 2)
			for (bx in 0...(w + 3) >> 2) {
				var a0 = bc.get(o), a1 = bc.get(o + 1);
				var pal = a0 > a1 ? [a0, a1].concat([for (k in 1...7) Std.int(((7 - k) * a0 + k * a1) / 7)]) : [a0, a1].concat([for (k in 1...5) Std.int(((5 - k) * a0 + k * a1) / 5)]).concat([0, 255]);
				var bits0 = bc.get(o + 2) | (bc.get(o + 3) << 8) | (bc.get(o + 4) << 16);
				var bits1 = bc.get(o + 5) | (bc.get(o + 6) << 8) | (bc.get(o + 7) << 16);
				for (i in 0...16) {
					var x = (bx << 2) + (i & 3), y = (by << 2) + (i >> 2);
					if (x >= w || y >= h)
						continue;
					var q = i < 8 ? (bits0 >> (i * 3)) & 7 : (bits1 >> ((i - 8) * 3)) & 7;
					var d = img.get((y * w + x) * 4 + channel) - pal[q];
					err += d * d;
					n++;
				}
				o += stride;
			}
		return err == 0 ? Math.POSITIVE_INFINITY : 10 * Math.log(255 * 255 / (err / n)) / Math.log(10);
	}
}
