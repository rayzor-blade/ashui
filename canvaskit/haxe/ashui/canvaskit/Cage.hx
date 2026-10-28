package ashui.canvaskit;

import ashui.draw3d.Material;
import ashui.draw3d.MeshData;
import ashui.math.Vec3;

/**
	A polygon control cage for Catmull-Clark subdivision modeling.

	Subdivision splits faces into quads and moves vertices toward a smooth
	surface. Faces use counter-clockwise winding when viewed from outside.
	Material slots let `meshes` split one surface into glass, paint, trim,
	or other regions. Boundary edges preserve openings such as wheel arches.

	Use `crease` for sharp edges. Infinite sharpness remains hard at every
	level; sharpness 2 stays sharp for two levels before smoothing. Mesh
	normals split across remaining sharp edges. See DeRose, Kass, and Truong,
	"Subdivision Surfaces in Character Animation" (1998).

	For symmetric models, build points with x >= 0 and put seam points at
	x = 0. `mirrored` creates the other half and joins the seam.
**/
class Cage {
	public final points:Array<Vec3> = [];

	/** Vertex indices per face, with counter-clockwise winding viewed from outside. **/
	public final faces:Array<Array<Int>> = [];

	/** Material slot for each face. **/
	public final slots:Array<Int> = [];

	final creases:Array<{a:Int, b:Int, sharpness:Float}> = [];

	public function new() {}

	/** Adds a point and returns its index. **/
	public function add(p:Vec3):Int {
		bounds = null;
		points.push(p);
		return points.length - 1;
	}

	/** Adds a face with outward counter-clockwise winding in the given material slot. Returns its index. **/
	public function face(ids:Array<Int>, slot = 0):Int {
		if (ids.length < 3)
			throw "a face needs at least three points";
		bounds = null;
		faces.push(ids.copy());
		slots.push(slot);
		return faces.length - 1;
	}

	/**
		Creates quads between equal-length rows of vertex indices. `wrap` joins
		the last and first point of each row, as for a tube. Order rows so a step
		along a row followed by a step to the next row winds counter-clockwise
		when viewed from outside.
	**/
	public function grid(rows:Array<Array<Int>>, slot = 0, wrap = false):Void {
		for (r in 0...rows.length - 1) {
			var a = rows[r], b = rows[r + 1];
			var count = wrap ? a.length : a.length - 1;
			for (i in 0...count) {
				var j = (i + 1) % a.length;
				face([a[i], a[j], b[j], b[i]], slot);
			}
		}
	}

	/** Creases an edge for the given subdivision levels. Omitted sharpness makes the edge infinitely sharp. **/
	public function crease(a:Int, b:Int, ?sharpness:Float):Void
		creases.push({a: a, b: b, sharpness: sharpness == null ? Math.POSITIVE_INFINITY : sharpness});

	/** Creases consecutive edges in `ids`, optionally joining the last point to the first. **/
	public function creaseLine(ids:Array<Int>, ?sharpness:Float, closed = false):Void {
		for (i in 0...ids.length - 1)
			crease(ids[i], ids[i + 1], sharpness);
		if (closed && ids.length > 2)
			crease(ids[ids.length - 1], ids[0], sharpness);
	}

	/** Returns edge sharpness, or zero for an uncreased edge. **/
	public function sharpness(a:Int, b:Int):Float {
		var s = 0.0;
		for (c in creases)
			if ((c.a == a && c.b == b) || (c.a == b && c.b == a))
				s = Math.max(s, c.sharpness);
		return s;
	}

	/**
		Mirrors the cage across x = 0 and joins both halves. Points within
		`tolerance` of the plane are snapped to the shared seam. Mirrored faces
		reverse winding to preserve outward normals.
	**/
	public function mirrored(tolerance = 1e-6):Cage {
		var out = new Cage();
		var twin = [];
		for (p in points) {
			var seam = Math.abs(p.x) <= tolerance;
			out.add(seam ? new Vec3(0, p.y, p.z) : p);
		}
		for (i in 0...points.length)
			twin.push(Math.abs(points[i].x) <= tolerance ? i : out.add(new Vec3(-points[i].x, points[i].y, points[i].z)));
		for (f in 0...faces.length)
			out.face(faces[f], slots[f]);
		for (f in 0...faces.length) {
			var ids = [for (i in 0...faces[f].length) twin[faces[f][faces[f].length - 1 - i]]];
			out.face(ids, slots[f]);
		}
		for (c in creases) {
			out.crease(c.a, c.b, c.sharpness);
			if (twin[c.a] != c.a || twin[c.b] != c.b)
				out.crease(twin[c.a], twin[c.b], c.sharpness);
		}
		return out;
	}

	/** Returns a cage after the given number of subdivision levels. **/
	public function subdivided(levels = 1):Cage {
		var cage = this;
		for (_ in 0...levels)
			cage = cage.step();
		return cage;
	}

	/** One level of Catmull-Clark subdivision, with semi-sharp creases. **/
	function step():Cage {
		var topo = new Topology(this);
		var n = points.length, edges = topo.a.length;
		var out = new Cage();
		var facePoint = [
			for (f in faces) {
				var sum = Vec3.ZERO;
				for (v in f)
					sum = sum.add(points[v]);
				sum.scale(1 / f.length);
			}
		];
		// Points in order: one for each old point, then each edge, then each face.
		var vertexPoints = [
			for (v in 0...n) {
				var p = points[v], incident = topo.vertexEdges[v];
				var sharpEnds = [], sharpness = 0.0, boundary = false;
				for (e in incident)
					if (topo.isSharp(e)) {
						sharpEnds.push(points[topo.other(e, v)]);
						var s = topo.faces[e].length < 2 ? Math.POSITIVE_INFINITY : topo.sharp[e];
						if (topo.faces[e].length < 2)
							boundary = true;
						sharpness += s;
					}
				var smooth = if (boundary || incident.length == 0) p else {
					var q = Vec3.ZERO, r = Vec3.ZERO, k = incident.length;
					for (f in topo.vertexFaces[v])
						q = q.add(facePoint[f]);
					q = q.scale(1 / topo.vertexFaces[v].length);
					for (e in incident)
						r = r.add(p.add(points[topo.other(e, v)]).scale(0.5));
					r = r.scale(1 / k);
					q.add(r.scale(2)).add(p.scale(k - 3)).scale(1 / k);
				};
				if (sharpEnds.length < 2)
					smooth;
				else {
					var vs = sharpness / sharpEnds.length;
					var hard = sharpEnds.length == 2 ? sharpEnds[0].add(sharpEnds[1]).add(p.scale(6)).scale(1 / 8) : p;
					vs >= 1 ? hard : smooth.lerp(hard, vs);
				}
			}
		];
		for (p in vertexPoints)
			out.add(p);
		for (e in 0...edges) {
			var pa = points[topo.a[e]], pb = points[topo.b[e]];
			var mid = pa.add(pb).scale(0.5);
			var adj = topo.faces[e];
			if (adj.length != 2)
				out.add(mid);
			else {
				var smooth = pa.add(pb).add(facePoint[adj[0]]).add(facePoint[adj[1]]).scale(0.25);
				var s = topo.sharp[e];
				out.add(s >= 1 ? mid : s > 0 ? smooth.lerp(mid, s) : smooth);
			}
		}
		for (p in facePoint)
			out.add(p);
		for (f in 0...faces.length) {
			var ids = faces[f], m = ids.length, centre = n + edges + f;
			for (i in 0...m) {
				var next = n + topo.faceEdges[f][i], prev = n + topo.faceEdges[f][(i + m - 1) % m];
				out.face([ids[i], next, centre, prev], slots[f]);
			}
		}
		// Each half of a sharp edge is one level less sharp; edges inside faces are smooth.
		for (e in 0...edges) {
			var s = topo.sharp[e] - 1;
			if (s > 0) {
				out.crease(topo.a[e], n + e, s);
				out.crease(n + e, topo.b[e], s);
			}
		}
		return out;
	}

	/**
		Builds one mesh per populated material slot using `materials[slot]`.
		Splits quads along the shorter diagonal. Normals remain smooth except
		across sharp edges and material-slot boundaries.
	**/
	public function meshes(materials:Array<Material>):Array<MeshData> {
		var topo = new Topology(this);
		var normal = [for (f in faces) newell(f)];
		// Each face corner, joined to the corners round the same point that it shades smoothly with.
		var base = [], count = 0;
		for (f in faces) {
			base.push(count);
			count += f.length;
		}
		var parent = [for (i in 0...count) i];
		function find(i:Int):Int {
			while (parent[i] != i) {
				parent[i] = parent[parent[i]];
				i = parent[i];
			}
			return i;
		}
		inline function corner(f:Int, v:Int):Int
			return base[f] + faces[f].indexOf(v);
		for (e in 0...topo.a.length) {
			var adj = topo.faces[e];
			if (adj.length != 2 || topo.sharp[e] > 0 || slots[adj[0]] != slots[adj[1]])
				continue;
			for (v in [topo.a[e], topo.b[e]]) {
				var x = find(corner(adj[0], v)), y = find(corner(adj[1], v));
				if (x != y)
					parent[x] = y;
			}
		}
		var sum = [for (_ in 0...count) Vec3.ZERO];
		for (f in 0...faces.length)
			for (i in 0...faces[f].length) {
				var g = find(base[f] + i);
				sum[g] = sum[g].add(normal[f]);
			}
		var out = [];
		var used = [for (s in slots) s];
		for (slot in 0...materials.length) {
			if (used.indexOf(slot) < 0)
				continue;
			var p:Array<Float> = [], nm:Array<Float> = [], idx:Array<Int> = [];
			var vertexOf = new Map<Int, Int>();
			for (f in 0...faces.length) {
				if (slots[f] != slot)
					continue;
				var ids = [
					for (i in 0...faces[f].length) {
						var g = find(base[f] + i);
						var known = vertexOf.get(g);
						if (known == null) {
							known = Std.int(p.length / 3);
							vertexOf.set(g, known);
							var at = points[faces[f][i]], dir = sum[g].normalize();
							p.push(at.x);
							p.push(at.y);
							p.push(at.z);
							nm.push(dir.x);
							nm.push(dir.y);
							nm.push(dir.z);
						}
						known;
					}
				];
				var f0 = faces[f];
				if (ids.length == 4 && points[f0[1]].distance(points[f0[3]]) < points[f0[0]].distance(points[f0[2]]))
					for (k in [ids[0], ids[1], ids[3], ids[1], ids[2], ids[3]])
						idx.push(k);
				else
					for (i in 1...ids.length - 1)
						for (k in [ids[0], ids[i], ids[i + 1]])
							idx.push(k);
			}
			out.push(MeshData.build(p, idx, nm, null, null, materials[slot]));
		}
		return out;
	}

	/**
		Finds the nearest surface point, outward normal, and face index.
		Use a subdivided cage to place details near the smooth surface. Face
		bounds are cached on the first query; finish moving points before querying.
	**/
	public function closest(p:Vec3):{point:Vec3, normal:Vec3, face:Int} {
		if (bounds == null || bounds.length != faces.length)
			bounds = [
				for (ids in faces) {
					var c = Vec3.ZERO;
					for (v in ids)
						c = c.add(points[v]);
					c = c.scale(1 / ids.length);
					var r = 0.0;
					for (v in ids)
						r = Math.max(r, points[v].distance(c));
					{centre: c, radius: r};
				}
			];
		var best = Math.POSITIVE_INFINITY, point = p, face = -1;
		function test(f:Int) {
			var b = bounds[f];
			if (p.distance(b.centre) - b.radius >= best)
				return;
			var ids = faces[f];
			for (i in 1...ids.length - 1) {
				var q = nearestOnTriangle(p, points[ids[0]], points[ids[i]], points[ids[i + 1]]);
				var d = q.distance(p);
				if (d < best) {
					best = d;
					point = q;
					face = f;
				}
			}
		}
		// The face last found first: neighbouring queries along a path are usually on it or near it, so the rest are culled sooner.
		if (lastFace >= 0 && lastFace < faces.length)
			test(lastFace);
		for (f in 0...faces.length)
			test(f);
		lastFace = face;
		return {point: point, normal: face >= 0 ? newell(faces[face]).normalize() : Vec3.UP, face: face};
	}

	var bounds:Null<Array<{centre:Vec3, radius:Float}>>;
	var lastFace = -1;

	/**
		Builds a surface band along a path, with width supplied by `width(f)`
		for path fractions from zero to one. Projects path points onto the
		surface and offsets the band by `lift`. Use a subdivided cage for details
		such as trim, lamps, handles, or panel lines.
	**/
	public function band(path:Array<Vec3>, width:Float->Float, lift:Float, ?material:Material):MeshData {
		var on = [for (q in path) closest(q)];
		var p:Array<Float> = [], n:Array<Float> = [], idx:Array<Int> = [];
		var last = on.length - 1;
		for (i in 0...on.length) {
			// The path's own direction, laid flat on the surface: two points of the path can land on the same point of it.
			var normal = on[i].normal;
			var along = path[i < last ? i + 1 : i].sub(path[i > 0 ? i - 1 : i]);
			along = along.sub(normal.scale(along.dot(normal)));
			var across = normal.cross(along).normalize().scale(width(last > 0 ? i / last : 0) / 2);
			var centre = on[i].point.add(normal.scale(lift));
			for (v in [centre.add(across), centre.sub(across)]) {
				p.push(v.x);
				p.push(v.y);
				p.push(v.z);
				n.push(normal.x);
				n.push(normal.y);
				n.push(normal.z);
			}
		}
		// Each pair is the left then the right of the path, seen from outside: quads counter-clockwise from the right.
		for (i in 0...last) {
			var l = i * 2, r = l + 1, l2 = l + 2, r2 = l + 3;
			for (k in [r, r2, l2, r, l2, l])
				idx.push(k);
		}
		return MeshData.build(p, idx, n, null, null, material);
	}

	/** Calculates an area-weighted polygon normal using Newell's method, including nonplanar faces. **/
	function newell(ids:Array<Int>):Vec3 {
		var x = 0.0, y = 0.0, z = 0.0;
		for (i in 0...ids.length) {
			var a = points[ids[i]], b = points[ids[(i + 1) % ids.length]];
			x += (a.y - b.y) * (a.z + b.z);
			y += (a.z - b.z) * (a.x + b.x);
			z += (a.x - b.x) * (a.y + b.y);
		}
		return new Vec3(x / 2, y / 2, z / 2);
	}

	/** Finds the nearest point on a triangle (Ericson, "Real-Time Collision Detection", section 5.1.5). **/
	static function nearestOnTriangle(p:Vec3, a:Vec3, b:Vec3, c:Vec3):Vec3 {
		var ab = b.sub(a), ac = c.sub(a), ap = p.sub(a);
		var d1 = ab.dot(ap), d2 = ac.dot(ap);
		if (d1 <= 0 && d2 <= 0)
			return a;
		var bp = p.sub(b), d3 = ab.dot(bp), d4 = ac.dot(bp);
		if (d3 >= 0 && d4 <= d3)
			return b;
		var vc = d1 * d4 - d3 * d2;
		if (vc <= 0 && d1 >= 0 && d3 <= 0)
			return a.add(ab.scale(d1 / (d1 - d3)));
		var cp = p.sub(c), d5 = ab.dot(cp), d6 = ac.dot(cp);
		if (d6 >= 0 && d5 <= d6)
			return c;
		var vb = d5 * d2 - d1 * d6;
		if (vb <= 0 && d2 >= 0 && d6 <= 0)
			return a.add(ac.scale(d2 / (d2 - d6)));
		var va = d3 * d6 - d5 * d4;
		if (va <= 0 && d4 - d3 >= 0 && d5 - d6 >= 0)
			return b.add(c.sub(b).scale((d4 - d3) / ((d4 - d3) + (d5 - d6))));
		var denom = 1 / (va + vb + vc);
		return a.add(ab.scale(vb * denom)).add(ac.scale(vc * denom));
	}
}

/** Edge adjacency, crease sharpness, and incident faces for cage vertices. **/
private class Topology {
	public final a:Array<Int> = [];
	public final b:Array<Int> = [];
	public final faces:Array<Array<Int>> = [];
	public final sharp:Array<Float> = [];
	public final vertexEdges:Array<Array<Int>>;
	public final vertexFaces:Array<Array<Int>>;

	/** Edge indices for each face, in face vertex order. **/
	public final faceEdges:Array<Array<Int>> = [];

	public function new(cage:Cage) {
		vertexEdges = [for (_ in cage.points) []];
		vertexFaces = [for (_ in cage.points) []];
		for (f in 0...cage.faces.length) {
			var ids = cage.faces[f];
			faceEdges.push([
				for (i in 0...ids.length) {
					var e = edge(ids[i], ids[(i + 1) % ids.length]);
					faces[e].push(f);
					e;
				}
			]);
			for (v in ids)
				vertexFaces[v].push(f);
		}
		for (e in 0...a.length)
			sharp[e] = cage.sharpness(a[e], b[e]);
	}

	function edge(u:Int, v:Int):Int {
		for (e in vertexEdges[u])
			if (a[e] == v || b[e] == v)
				return e;
		var e = a.length;
		a.push(u);
		b.push(v);
		faces.push([]);
		sharp.push(0);
		vertexEdges[u].push(e);
		vertexEdges[v].push(e);
		return e;
	}

	public inline function other(e:Int, v:Int):Int
		return a[e] == v ? b[e] : a[e];

	/** Returns whether an edge is a crease or boundary. **/
	public inline function isSharp(e:Int):Bool
		return sharp[e] > 0 || faces[e].length < 2;
}
