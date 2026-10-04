package ashui.math;

/** A point or direction in 3D. Immutable: each operation makes a new one. **/
class Vec3 {
	public static final ZERO = new Vec3(0, 0, 0);
	public static final ONE = new Vec3(1, 1, 1);

	/** Up, as the camera and glTF have it: +Y. **/
	public static final UP = new Vec3(0, 1, 0);

	public final x:Float;
	public final y:Float;
	public final z:Float;

	public inline function new(x:Float, y:Float, z:Float) {
		this.x = x;
		this.y = y;
		this.z = z;
	}

	public inline function add(v:Vec3):Vec3
		return new Vec3(x + v.x, y + v.y, z + v.z);

	public inline function sub(v:Vec3):Vec3
		return new Vec3(x - v.x, y - v.y, z - v.z);

	public inline function scale(s:Float):Vec3
		return new Vec3(x * s, y * s, z * s);

	/** Each component times `v`'s. **/
	public inline function mul(v:Vec3):Vec3
		return new Vec3(x * v.x, y * v.y, z * v.z);

	public inline function negate():Vec3
		return new Vec3(-x, -y, -z);

	public inline function dot(v:Vec3):Float
		return x * v.x + y * v.y + z * v.z;

	public inline function cross(v:Vec3):Vec3
		return new Vec3(y * v.z - z * v.y, z * v.x - x * v.z, x * v.y - y * v.x);

	public inline function length():Float
		return Math.sqrt(x * x + y * y + z * z);

	/** This at length 1, or zero for zero. **/
	public function normalize():Vec3 {
		var l = length();
		return l > 0 ? new Vec3(x / l, y / l, z / l) : ZERO;
	}

	public inline function lerp(to:Vec3, t:Float):Vec3
		return new Vec3(x + (to.x - x) * t, y + (to.y - y) * t, z + (to.z - z) * t);

	public inline function distance(v:Vec3):Float
		return sub(v).length();

	public function toString():String
		return '($x, $y, $z)';
}
