package ashui.math;

import haxe.ds.Vector;

/**
	A 4×4 transform in 3D, column-major as WGSL's `mat4x4<f32>` reads it:
	`get(column, row)`. Points are columns, so `a.mul(b)` applies `b`
	first. Immutable.

	Cameras look down -Z with +Y up, and projections map depth to 0 at the
	near plane and 1 at the far one, as WebGPU clips.
**/
class Mat4 {
	public static final IDENTITY = new Mat4(Vector.fromArrayCopy([1.0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]));

	/** The sixteen values, column by column. **/
	public final m:Vector<Float>;

	function new(m:Vector<Float>)
		this.m = m;

	/** From sixteen values, column by column. **/
	public static function ofColumns(values:Array<Float>):Mat4 {
		if (values.length != 16)
			throw "Mat4.ofColumns: 16 values";
		return new Mat4(Vector.fromArrayCopy(values));
	}

	public inline function get(column:Int, row:Int):Float
		return m[column * 4 + row];

	public static function translation(v:Vec3):Mat4
		return ofColumns([1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, v.x, v.y, v.z, 1]);

	public static function scaling(v:Vec3):Mat4
		return ofColumns([v.x, 0, 0, 0, 0, v.y, 0, 0, 0, 0, v.z, 0, 0, 0, 0, 1]);

	public static function rotation(q:Quat):Mat4 {
		var x = q.x, y = q.y, z = q.z, w = q.w;
		return ofColumns([
			1 - 2 * (y * y + z * z), 2 * (x * y + z * w), 2 * (x * z - y * w), 0,
			2 * (x * y - z * w), 1 - 2 * (x * x + z * z), 2 * (y * z + x * w), 0,
			2 * (x * z + y * w), 2 * (y * z - x * w), 1 - 2 * (x * x + y * y), 0,
			0, 0, 0, 1
		]);
	}

	/** Scaled, then turned, then moved: a node's transform. **/
	public static function compose(position:Vec3, rotation:Quat, scale:Vec3):Mat4 {
		var r = Mat4.rotation(rotation).m;
		return ofColumns([
			r[0] * scale.x, r[1] * scale.x, r[2] * scale.x, 0,
			r[4] * scale.y, r[5] * scale.y, r[6] * scale.y, 0,
			r[8] * scale.z, r[9] * scale.z, r[10] * scale.z, 0,
			position.x, position.y, position.z, 1
		]);
	}

	/** A perspective projection: `fovY` radians from bottom to top, `aspect` width over height. **/
	public static function perspective(fovY:Float, aspect:Float, near:Float, far:Float):Mat4 {
		var f = 1 / Math.tan(fovY / 2);
		var range = 1 / (near - far);
		return ofColumns([f / aspect, 0, 0, 0, 0, f, 0, 0, 0, 0, far * range, -1, 0, 0, near * far * range, 0]);
	}

	/** An orthographic projection of the box between the planes given. **/
	public static function orthographic(left:Float, right:Float, bottom:Float, top:Float, near:Float, far:Float):Mat4 {
		var w = 1 / (right - left), h = 1 / (top - bottom), d = 1 / (near - far);
		return ofColumns([2 * w, 0, 0, 0, 0, 2 * h, 0, 0, 0, 0, d, 0, -(right + left) * w, -(top + bottom) * h, near * d, 1]);
	}

	/** The view from `eye` toward `target`, `up` keeping it level. **/
	public static function lookAt(eye:Vec3, target:Vec3, up:Vec3):Mat4 {
		var f = target.sub(eye).normalize();
		var s = f.cross(up).normalize();
		if (s.length() == 0)
			s = f.cross(Math.abs(f.z) < 0.9 ? new Vec3(0, 0, 1) : new Vec3(1, 0, 0)).normalize();
		var u = s.cross(f);
		return ofColumns([s.x, u.x, -f.x, 0, s.y, u.y, -f.y, 0, s.z, u.z, -f.z, 0, -s.dot(eye), -u.dot(eye), f.dot(eye), 1]);
	}

	/** This after `b`: `b` applied first. **/
	public function mul(b:Mat4):Mat4 {
		var a = m, o = new Vector<Float>(16);
		for (c in 0...4)
			for (r in 0...4)
				o[c * 4 + r] = a[r] * b.m[c * 4] + a[4 + r] * b.m[c * 4 + 1] + a[8 + r] * b.m[c * 4 + 2] + a[12 + r] * b.m[c * 4 + 3];
		return new Mat4(o);
	}

	public function transpose():Mat4 {
		var o = new Vector<Float>(16);
		for (c in 0...4)
			for (r in 0...4)
				o[c * 4 + r] = m[r * 4 + c];
		return new Mat4(o);
	}

	/** The inverse, or null where there is none. **/
	public function inverse():Null<Mat4> {
		var a = m, inv = new Vector<Float>(16);
		inv[0] = a[5] * a[10] * a[15] - a[5] * a[11] * a[14] - a[9] * a[6] * a[15] + a[9] * a[7] * a[14] + a[13] * a[6] * a[11] - a[13] * a[7] * a[10];
		inv[4] = -a[4] * a[10] * a[15] + a[4] * a[11] * a[14] + a[8] * a[6] * a[15] - a[8] * a[7] * a[14] - a[12] * a[6] * a[11] + a[12] * a[7] * a[10];
		inv[8] = a[4] * a[9] * a[15] - a[4] * a[11] * a[13] - a[8] * a[5] * a[15] + a[8] * a[7] * a[13] + a[12] * a[5] * a[11] - a[12] * a[7] * a[9];
		inv[12] = -a[4] * a[9] * a[14] + a[4] * a[10] * a[13] + a[8] * a[5] * a[14] - a[8] * a[6] * a[13] - a[12] * a[5] * a[10] + a[12] * a[6] * a[9];
		inv[1] = -a[1] * a[10] * a[15] + a[1] * a[11] * a[14] + a[9] * a[2] * a[15] - a[9] * a[3] * a[14] - a[13] * a[2] * a[11] + a[13] * a[3] * a[10];
		inv[5] = a[0] * a[10] * a[15] - a[0] * a[11] * a[14] - a[8] * a[2] * a[15] + a[8] * a[3] * a[14] + a[12] * a[2] * a[11] - a[12] * a[3] * a[10];
		inv[9] = -a[0] * a[9] * a[15] + a[0] * a[11] * a[13] + a[8] * a[1] * a[15] - a[8] * a[3] * a[13] - a[12] * a[1] * a[11] + a[12] * a[3] * a[9];
		inv[13] = a[0] * a[9] * a[14] - a[0] * a[10] * a[13] - a[8] * a[1] * a[14] + a[8] * a[2] * a[13] + a[12] * a[1] * a[10] - a[12] * a[2] * a[9];
		inv[2] = a[1] * a[6] * a[15] - a[1] * a[7] * a[14] - a[5] * a[2] * a[15] + a[5] * a[3] * a[14] + a[13] * a[2] * a[7] - a[13] * a[3] * a[6];
		inv[6] = -a[0] * a[6] * a[15] + a[0] * a[7] * a[14] + a[4] * a[2] * a[15] - a[4] * a[3] * a[14] - a[12] * a[2] * a[7] + a[12] * a[3] * a[6];
		inv[10] = a[0] * a[5] * a[15] - a[0] * a[7] * a[13] - a[4] * a[1] * a[15] + a[4] * a[3] * a[13] + a[12] * a[1] * a[7] - a[12] * a[3] * a[5];
		inv[14] = -a[0] * a[5] * a[14] + a[0] * a[6] * a[13] + a[4] * a[1] * a[14] - a[4] * a[2] * a[13] - a[12] * a[1] * a[6] + a[12] * a[2] * a[5];
		inv[3] = -a[1] * a[6] * a[11] + a[1] * a[7] * a[10] + a[5] * a[2] * a[11] - a[5] * a[3] * a[10] - a[9] * a[2] * a[7] + a[9] * a[3] * a[6];
		inv[7] = a[0] * a[6] * a[11] - a[0] * a[7] * a[10] - a[4] * a[2] * a[11] + a[4] * a[3] * a[10] + a[8] * a[2] * a[7] - a[8] * a[3] * a[6];
		inv[11] = -a[0] * a[5] * a[11] + a[0] * a[7] * a[9] + a[4] * a[1] * a[11] - a[4] * a[3] * a[9] - a[8] * a[1] * a[7] + a[8] * a[3] * a[5];
		inv[15] = a[0] * a[5] * a[10] - a[0] * a[6] * a[9] - a[4] * a[1] * a[10] + a[4] * a[2] * a[9] + a[8] * a[1] * a[6] - a[8] * a[2] * a[5];
		var det = a[0] * inv[0] + a[1] * inv[4] + a[2] * inv[8] + a[3] * inv[12];
		if (Math.abs(det) < 1e-12)
			return null;
		for (i in 0...16)
			inv[i] /= det;
		return new Mat4(inv);
	}

	/** What turns normals as this turns surfaces: the inverse transpose, its translation dropped. **/
	public function normalMatrix():Mat4 {
		var inv = inverse();
		if (inv == null)
			return IDENTITY;
		var t = inv.transpose().m;
		return ofColumns([t[0], t[1], t[2], 0, t[4], t[5], t[6], 0, t[8], t[9], t[10], 0, 0, 0, 0, 1]);
	}

	/** `p` through this, divided by its w. **/
	public function transformPoint(p:Vec3):Vec3 {
		var w = m[3] * p.x + m[7] * p.y + m[11] * p.z + m[15];
		var s = w != 0 ? 1 / w : 1;
		return new Vec3((m[0] * p.x + m[4] * p.y + m[8] * p.z + m[12]) * s, (m[1] * p.x + m[5] * p.y + m[9] * p.z + m[13]) * s,
			(m[2] * p.x + m[6] * p.y + m[10] * p.z + m[14]) * s);
	}

	/** `d` through this without its translation. **/
	public function transformDirection(d:Vec3):Vec3
		return new Vec3(m[0] * d.x + m[4] * d.y + m[8] * d.z, m[1] * d.x + m[5] * d.y + m[9] * d.z, m[2] * d.x + m[6] * d.y + m[10] * d.z);

	/** Where this moves the origin. **/
	public function position():Vec3
		return new Vec3(m[12], m[13], m[14]);

	/** Writes the sixteen values as 32-bit floats into `out` at byte `offset`, as a WGSL `mat4x4<f32>` reads them. **/
	public function write(out:haxe.io.Bytes, offset:Int):Void
		for (i in 0...16)
			out.setFloat(offset + i * 4, m[i]);
}
