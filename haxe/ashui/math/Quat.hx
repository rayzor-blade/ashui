package ashui.math;

/** A rotation, as a unit quaternion. Immutable. **/
class Quat {
	public static final IDENTITY = new Quat(0, 0, 0, 1);

	public final x:Float;
	public final y:Float;
	public final z:Float;
	public final w:Float;

	public inline function new(x:Float, y:Float, z:Float, w:Float) {
		this.x = x;
		this.y = y;
		this.z = z;
		this.w = w;
	}

	/** Turning by `radians` about `axis`, counter-clockwise looking down the axis toward the origin. **/
	public static function axisAngle(axis:Vec3, radians:Float):Quat {
		var a = axis.normalize(), s = Math.sin(radians / 2);
		return new Quat(a.x * s, a.y * s, a.z * s, Math.cos(radians / 2));
	}

	/** Turning about X by `x`, then Y by `y`, then Z by `z`, in radians. **/
	public static function euler(x:Float, y:Float, z:Float):Quat
		return axisAngle(new Vec3(0, 0, 1), z).mul(axisAngle(Vec3.UP, y)).mul(axisAngle(new Vec3(1, 0, 0), x));

	/** This after `q`: `q`'s rotation first, then this one. **/
	public inline function mul(q:Quat):Quat
		return new Quat(w * q.x + x * q.w + y * q.z - z * q.y, w * q.y - x * q.z + y * q.w + z * q.x, w * q.z + x * q.y - y * q.x + z * q.w,
			w * q.w - x * q.x - y * q.y - z * q.z);

	public inline function conjugate():Quat
		return new Quat(-x, -y, -z, w);

	public function normalize():Quat {
		var l = Math.sqrt(x * x + y * y + z * z + w * w);
		return l > 0 ? new Quat(x / l, y / l, z / l, w / l) : IDENTITY;
	}

	/** `v` turned by this. **/
	public function rotate(v:Vec3):Vec3 {
		var u = new Vec3(x, y, z);
		var t = u.cross(v).scale(2);
		return v.add(t.scale(w)).add(u.cross(t));
	}

	/** The way between this and `to`, the shorter one, at `t` from 0 to 1. **/
	public function slerp(to:Quat, t:Float):Quat {
		var d = x * to.x + y * to.y + z * to.z + w * to.w;
		var b = to;
		if (d < 0) {
			d = -d;
			b = new Quat(-to.x, -to.y, -to.z, -to.w);
		}
		if (d > 0.9995)
			return new Quat(x + (b.x - x) * t, y + (b.y - y) * t, z + (b.z - z) * t, w + (b.w - w) * t).normalize();
		var theta = Math.acos(d), s = Math.sin(theta);
		var wa = Math.sin((1 - t) * theta) / s, wb = Math.sin(t * theta) / s;
		return new Quat(x * wa + b.x * wb, y * wa + b.y * wb, z * wa + b.z * wb, w * wa + b.w * wb);
	}
}
