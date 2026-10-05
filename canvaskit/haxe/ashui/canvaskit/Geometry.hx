package ashui.canvaskit;

import ashui.draw3d.Material;
import ashui.draw3d.MeshData;
import ashui.math.Vec3;

/**
	Meshes of simple shapes, centred on the origin, with normals, texture
	coordinates and tangents, made of `material` (`Material.DEFAULT` when
	it is left out). Curved ones take how many pieces to make them of.
**/
class Geometry {
	/** A box `width` by `height` by `depth`, each face its own four vertices so its edges stay sharp. **/
	public static function box(width = 1.0, height = 1.0, depth = 1.0, ?material:Material):MeshData {
		var p:Array<Float> = [], n:Array<Float> = [], uv:Array<Float> = [], idx:Array<Int> = [];
		var half = new Vec3(width / 2, height / 2, depth / 2);
		for (f in [[1, 0, 0], [-1, 0, 0], [0, 1, 0], [0, -1, 0], [0, 0, 1], [0, 0, -1]]) {
			var normal = new Vec3(f[0], f[1], f[2]);
			// u and v across the face, u x v along its normal, so the corners run counter-clockwise seen from outside.
			var u = Math.abs(normal.y) > 0.5 ? new Vec3(1, 0, 0) : new Vec3(-normal.z, 0, normal.x);
			var v = normal.cross(u);
			var base = Std.int(p.length / 3);
			for (c in [[-1, -1], [1, -1], [1, 1], [-1, 1]]) {
				var q = normal.add(u.scale(c[0])).add(v.scale(c[1])).mul(half);
				p.push(q.x);
				p.push(q.y);
				p.push(q.z);
				n.push(normal.x);
				n.push(normal.y);
				n.push(normal.z);
				uv.push((c[0] + 1) / 2);
				uv.push((1 - c[1]) / 2);
			}
			for (i in [0, 1, 2, 0, 2, 3])
				idx.push(base + i);
		}
		return MeshData.build(p, idx, n, uv, null, material);
	}

	/** A sphere of `radius`, in `rings` from pole to pole and `segments` round. **/
	public static function sphere(radius = 0.5, rings = 32, segments = 48, ?material:Material):MeshData {
		var p:Array<Float> = [], n:Array<Float> = [], uv:Array<Float> = [], idx:Array<Int> = [];
		for (r in 0...rings + 1) {
			var phi = r / rings * Math.PI;
			for (s in 0...segments + 1) {
				var theta = s / segments * Math.PI * 2;
				var x = -Math.cos(theta) * Math.sin(phi), y = Math.cos(phi), z = Math.sin(theta) * Math.sin(phi);
				p.push(x * radius);
				p.push(y * radius);
				p.push(z * radius);
				n.push(x);
				n.push(y);
				n.push(z);
				uv.push(s / segments);
				uv.push(r / rings);
			}
		}
		for (r in 0...rings)
			for (s in 0...segments) {
				var a = r * (segments + 1) + s, b = a + segments + 1;
				for (i in [a, b, a + 1, a + 1, b, b + 1])
					idx.push(i);
			}
		return MeshData.build(p, idx, n, uv, null, material);
	}

	/** A flat square `width` by `depth` on the ground, facing up, in `divisions` each way. **/
	public static function plane(width = 1.0, depth = 1.0, divisions = 1, ?material:Material):MeshData {
		var p:Array<Float> = [], n:Array<Float> = [], uv:Array<Float> = [], idx:Array<Int> = [];
		var d = Std.int(Math.max(1, divisions));
		for (j in 0...d + 1)
			for (i in 0...d + 1) {
				p.push((i / d - 0.5) * width);
				p.push(0);
				p.push((j / d - 0.5) * depth);
				n.push(0);
				n.push(1);
				n.push(0);
				uv.push(i / d);
				uv.push(j / d);
			}
		for (j in 0...d)
			for (i in 0...d) {
				var a = j * (d + 1) + i, b = a + d + 1;
				for (k in [a, b, a + 1, a + 1, b, b + 1])
					idx.push(k);
			}
		return MeshData.build(p, idx, n, uv, null, material);
	}

	/**
		Ground `width` by `depth`, centred on the origin, raised by
		`heightMap`: its brightness 0 at the plane, `height` at white, in
		`divisions` each way, each vertex the map's pixel there. Its texture
		coordinates run 0 to 1 across, so a material's `textureTransform`
		repeats a texture over it. For a terrain's map of heights, or a
		material's displacement map.
	**/
	public static function terrain(heightMap:ashui.types.Bitmap, width = 10.0, depth = 10.0, height = 1.0, divisions = 256,
			?material:Material):MeshData {
		var d = Std.int(Math.max(1, divisions));
		var px = heightMap.pixels(d + 1, d + 1);
		if (px == null)
			throw "terrain: the height map's pixels are freed";
		return heightField(width, depth, d, (i, j) -> {
			// Past the edge, the edge's own height.
			i = i < 0 ? 0 : i > d ? d : i;
			j = j < 0 ? 0 : j > d ? d : j;
			var at = (j * (d + 1) + i) * 4;
			(px.get(at) + px.get(at + 1) + px.get(at + 2)) / (3 * 255) * height;
		}, material);
	}

	/**
		Ground `width` by `depth`, centred on the origin, in `divisions` each
		way, each vertex `heightAt(i, j)` above the plane, `i` across and `j`
		into the scene, both 0 to `divisions`; normals from the heights'
		slopes, texture coordinates 0 to 1 across. `heightAt` is asked one
		step past each edge too, for the slopes there: ground made in pieces
		side by side, each asked the heights of one surface, meets without a
		seam in its shading.
	**/
	public static function heightField(width:Float, depth:Float, divisions:Int, heightAt:(i:Int, j:Int) -> Float, ?material:Material):MeshData {
		var d = Std.int(Math.max(1, divisions)), w = d + 1, ring = d + 3;
		// Heights from -1 to d + 1 each way: a ring past the edges.
		var h = [for (j in -1...d + 2) for (i in -1...d + 2) heightAt(i, j)];
		var p:Array<Float> = [], n:Array<Float> = [], uv:Array<Float> = [], idx:Array<Int> = [];
		var dx = width / d, dz = depth / d;
		inline function at(i:Int, j:Int)
			return h[(j + 1) * ring + i + 1];
		for (j in 0...w)
			for (i in 0...w) {
				p.push((i / d - 0.5) * width);
				p.push(at(i, j));
				p.push((j / d - 0.5) * depth);
				// The slope each way, by the neighbours on either side; the normal leans away from it.
				var sx = (at(i + 1, j) - at(i - 1, j)) / (2 * dx), sz = (at(i, j + 1) - at(i, j - 1)) / (2 * dz);
				var len = Math.sqrt(sx * sx + 1 + sz * sz);
				n.push(-sx / len);
				n.push(1 / len);
				n.push(-sz / len);
				uv.push(i / d);
				uv.push(j / d);
			}
		for (j in 0...d)
			for (i in 0...d) {
				var a = j * w + i, b = a + w;
				for (k in [a, b, a + 1, a + 1, b, b + 1])
					idx.push(k);
			}
		return MeshData.build(p, idx, n, uv, null, material);
	}

	/** An upright cylinder of `radius` and `height`, closed at both ends, in `segments` round. **/
	public static function cylinder(radius = 0.5, height = 1.0, segments = 48, ?material:Material):MeshData {
		var p:Array<Float> = [], n:Array<Float> = [], uv:Array<Float> = [], idx:Array<Int> = [];
		inline function vertex(x:Float, y:Float, z:Float, nx:Float, ny:Float, nz:Float, u:Float, v:Float) {
			p.push(x);
			p.push(y);
			p.push(z);
			n.push(nx);
			n.push(ny);
			n.push(nz);
			uv.push(u);
			uv.push(v);
		}
		var h = height / 2;
		for (s in 0...segments + 1) {
			var t = s / segments * Math.PI * 2;
			var x = Math.sin(t), z = Math.cos(t);
			vertex(x * radius, h, z * radius, x, 0, z, s / segments, 0);
			vertex(x * radius, -h, z * radius, x, 0, z, s / segments, 1);
		}
		for (s in 0...segments) {
			var a = s * 2;
			for (i in [a, a + 1, a + 2, a + 2, a + 1, a + 3])
				idx.push(i);
		}
		for (cap in [1, -1]) {
			var centre = Std.int(p.length / 3);
			vertex(0, h * cap, 0, 0, cap, 0, 0.5, 0.5);
			for (s in 0...segments + 1) {
				var t = s / segments * Math.PI * 2;
				vertex(Math.sin(t) * radius, h * cap, Math.cos(t) * radius, 0, cap, 0, 0.5 + Math.sin(t) / 2, 0.5 + Math.cos(t) / 2);
			}
			for (s in 0...segments) {
				if (cap > 0)
					for (i in [centre, centre + 1 + s, centre + 2 + s])
						idx.push(i);
				else
					for (i in [centre, centre + 2 + s, centre + 1 + s])
						idx.push(i);
			}
		}
		return MeshData.build(p, idx, n, uv, null, material);
	}

	/** A ring lying flat, `radius` to the middle of its tube and the tube `tube` thick, in `rings` round and `sides` round the tube. **/
	public static function torus(radius = 0.5, tube = 0.2, rings = 48, sides = 24, ?material:Material):MeshData {
		var p:Array<Float> = [], n:Array<Float> = [], uv:Array<Float> = [], idx:Array<Int> = [];
		for (r in 0...rings + 1) {
			var u = r / rings * Math.PI * 2;
			var cx = Math.sin(u), cz = Math.cos(u);
			for (s in 0...sides + 1) {
				var v = s / sides * Math.PI * 2;
				var nx = cx * Math.cos(v), ny = Math.sin(v), nz = cz * Math.cos(v);
				p.push(cx * radius + nx * tube);
				p.push(ny * tube);
				p.push(cz * radius + nz * tube);
				n.push(nx);
				n.push(ny);
				n.push(nz);
				uv.push(r / rings);
				uv.push(s / sides);
			}
		}
		for (r in 0...rings)
			for (s in 0...sides) {
				var a = r * (sides + 1) + s, b = a + sides + 1;
				for (i in [a, b, a + 1, a + 1, b, b + 1])
					idx.push(i);
			}
		return MeshData.build(p, idx, n, uv, null, material);
	}
}
