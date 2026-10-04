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
