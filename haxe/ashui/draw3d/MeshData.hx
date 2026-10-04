package ashui.draw3d;

import ashui.math.Vec3;
import haxe.io.Bytes;

/**
	Triangles to draw in 3D, and the material they are made of. Each vertex
	has a position, a normal (the way its surface faces), a texture
	coordinate and a tangent (the way the texture's x runs along the
	surface, which normal textures need); each three `indices` name a
	triangle's vertices, counter-clockwise seen from its front.

	`build` makes one from arrays, working out normals and tangents left
	out. The vertices are kept as the GPU reads them, `STRIDE` bytes each,
	and uploaded once, the first time the mesh is drawn.
**/
class MeshData {
	/** Bytes to a vertex: position, normal, texture coordinate, tangent, as 32-bit floats. **/
	public static inline var STRIDE = 48;

	public static inline var POSITION_OFFSET = 0;
	public static inline var NORMAL_OFFSET = 12;
	public static inline var UV_OFFSET = 24;
	public static inline var TANGENT_OFFSET = 32;

	public final vertices:Bytes;
	public final indices:Bytes;
	public final vertexCount:Int;
	public final indexCount:Int;
	public final material:Material;

	/** The corners of the box around the vertices. **/
	public final min:Vec3;

	public final max:Vec3;

	/** From vertices already laid out as `STRIDE` says, and 32-bit indices. **/
	public function new(vertices:Bytes, indices:Bytes, material:Material) {
		this.vertices = vertices;
		this.indices = indices;
		this.material = material;
		vertexCount = Std.int(vertices.length / STRIDE);
		indexCount = indices.length >> 2;
		var x0 = Math.POSITIVE_INFINITY, y0 = Math.POSITIVE_INFINITY, z0 = Math.POSITIVE_INFINITY;
		var x1 = Math.NEGATIVE_INFINITY, y1 = Math.NEGATIVE_INFINITY, z1 = Math.NEGATIVE_INFINITY;
		for (i in 0...vertexCount) {
			var x = vertices.getFloat(i * STRIDE), y = vertices.getFloat(i * STRIDE + 4), z = vertices.getFloat(i * STRIDE + 8);
			x0 = Math.min(x0, x);
			y0 = Math.min(y0, y);
			z0 = Math.min(z0, z);
			x1 = Math.max(x1, x);
			y1 = Math.max(y1, y);
			z1 = Math.max(z1, z);
		}
		min = vertexCount > 0 ? new Vec3(x0, y0, z0) : Vec3.ZERO;
		max = vertexCount > 0 ? new Vec3(x1, y1, z1) : Vec3.ZERO;
	}

	/** A copy drawn with `material`, sharing the vertices. **/
	public function withMaterial(material:Material):MeshData
		return new MeshData(vertices, indices, material);

	/**
		From `positions`, three numbers a vertex, and `indices`, three a
		triangle; `normals` (three a vertex) worked out from the triangles
		when left out, smooth across shared vertices; `uvs` (two a vertex)
		zero when left out; `tangents` (four a vertex, the fourth the
		handedness, 1 or -1) worked out from the uvs when left out.
	**/
	public static function build(positions:Array<Float>, indices:Array<Int>, ?normals:Array<Float>, ?uvs:Array<Float>, ?tangents:Array<Float>,
			?material:Material):MeshData {
		var n = Std.int(positions.length / 3);
		if (normals == null)
			normals = smoothNormals(positions, indices);
		if (tangents == null)
			tangents = uvs != null ? tangentsOf(positions, normals, uvs, indices) : [for (_ in 0...n) for (v in [1.0, 0, 0, 1]) v];
		var out = Bytes.alloc(n * STRIDE);
		for (i in 0...n) {
			var o = i * STRIDE;
			for (k in 0...3) {
				out.setFloat(o + k * 4, positions[i * 3 + k]);
				out.setFloat(o + NORMAL_OFFSET + k * 4, normals[i * 3 + k]);
			}
			out.setFloat(o + UV_OFFSET, uvs != null ? uvs[i * 2] : 0);
			out.setFloat(o + UV_OFFSET + 4, uvs != null ? uvs[i * 2 + 1] : 0);
			for (k in 0...4)
				out.setFloat(o + TANGENT_OFFSET + k * 4, tangents[i * 4 + k]);
		}
		var idx = Bytes.alloc(indices.length * 4);
		for (i in 0...indices.length)
			idx.setInt32(i * 4, indices[i]);
		return new MeshData(out, idx, material != null ? material : Material.DEFAULT);
	}

	/** Each vertex's normal, the triangles around it summed, weighted by their area. **/
	public static function smoothNormals(positions:Array<Float>, indices:Array<Int>):Array<Float> {
		var out = [for (_ in 0...positions.length) 0.0];
		var t = 0;
		while (t + 2 < indices.length) {
			var a = indices[t], b = indices[t + 1], c = indices[t + 2];
			var pa = at(positions, a), pb = at(positions, b), pc = at(positions, c);
			var face = pb.sub(pa).cross(pc.sub(pa));
			for (v in [a, b, c]) {
				out[v * 3] += face.x;
				out[v * 3 + 1] += face.y;
				out[v * 3 + 2] += face.z;
			}
			t += 3;
		}
		for (v in 0...Std.int(out.length / 3)) {
			var nv = new Vec3(out[v * 3], out[v * 3 + 1], out[v * 3 + 2]).normalize();
			out[v * 3] = nv.x;
			out[v * 3 + 1] = nv.y;
			out[v * 3 + 2] = nv.z;
		}
		return out;
	}

	/** Each vertex's tangent from how its triangles' texture coordinates run, made perpendicular to its normal. **/
	public static function tangentsOf(positions:Array<Float>, normals:Array<Float>, uvs:Array<Float>, indices:Array<Int>):Array<Float> {
		var n = Std.int(positions.length / 3);
		var tan = [for (_ in 0...n * 3) 0.0], bit = [for (_ in 0...n * 3) 0.0];
		var t = 0;
		while (t + 2 < indices.length) {
			var a = indices[t], b = indices[t + 1], c = indices[t + 2];
			var e1 = at(positions, b).sub(at(positions, a)), e2 = at(positions, c).sub(at(positions, a));
			var du1 = uvs[b * 2] - uvs[a * 2], dv1 = uvs[b * 2 + 1] - uvs[a * 2 + 1];
			var du2 = uvs[c * 2] - uvs[a * 2], dv2 = uvs[c * 2 + 1] - uvs[a * 2 + 1];
			var det = du1 * dv2 - du2 * dv1;
			if (Math.abs(det) > 1e-12) {
				var r = 1 / det;
				var sd = e1.scale(dv2).sub(e2.scale(dv1)).scale(r);
				var td = e2.scale(du1).sub(e1.scale(du2)).scale(r);
				for (v in [a, b, c]) {
					tan[v * 3] += sd.x;
					tan[v * 3 + 1] += sd.y;
					tan[v * 3 + 2] += sd.z;
					bit[v * 3] += td.x;
					bit[v * 3 + 1] += td.y;
					bit[v * 3 + 2] += td.z;
				}
			}
			t += 3;
		}
		var out = [];
		for (v in 0...n) {
			var nv = at(normals, v), tv = at(tan, v);
			var ortho = tv.sub(nv.scale(nv.dot(tv))).normalize();
			if (ortho.length() == 0)
				ortho = nv.cross(Math.abs(nv.y) < 0.99 ? Vec3.UP : new Vec3(1, 0, 0)).normalize();
			var w = nv.cross(ortho).dot(at(bit, v)) < 0 ? -1.0 : 1.0;
			out.push(ortho.x);
			out.push(ortho.y);
			out.push(ortho.z);
			out.push(w);
		}
		return out;
	}

	static inline function at(a:Array<Float>, i:Int):Vec3
		return new Vec3(a[i * 3], a[i * 3 + 1], a[i * 3 + 2]);
}
