package ashui.draw;

/**
	A 2D affine transform: `x' = a·x + c·y + e`, `y' = b·x + d·y + f`, the
	layout of SVG's and the display list's matrices. Immutable; each
	operation returns a new one.
**/
class Affine {
	public final a:Float;
	public final b:Float;
	public final c:Float;
	public final d:Float;
	public final e:Float;
	public final f:Float;

	public static final IDENTITY = new Affine(1, 0, 0, 1, 0, 0);

	public function new(a:Float, b:Float, c:Float, d:Float, e:Float, f:Float) {
		this.a = a;
		this.b = b;
		this.c = c;
		this.d = d;
		this.e = e;
		this.f = f;
	}

	public static inline function translation(x:Float, y:Float):Affine
		return new Affine(1, 0, 0, 1, x, y);

	public static inline function scaling(x:Float, y:Float):Affine
		return new Affine(x, 0, 0, y, 0, 0);

	/** Turned by `radians`, clockwise on screen where y grows down. **/
	public static function rotation(radians:Float):Affine {
		var cos = Math.cos(radians), sin = Math.sin(radians);
		return new Affine(cos, sin, -sin, cos, 0, 0);
	}

	/** This one after `inner`: a point goes through `inner` first. **/
	public function after(inner:Affine):Affine
		return new Affine(a * inner.a + c * inner.b, b * inner.a + d * inner.b, a * inner.c + c * inner.d, b * inner.c + d * inner.d,
			a * inner.e + c * inner.f + e, b * inner.e + d * inner.f + f);

	public inline function x(px:Float, py:Float):Float
		return a * px + c * py + e;

	public inline function y(px:Float, py:Float):Float
		return b * px + d * py + f;

	/** How much it scales lengths, on average over directions: what a tolerance or a line width is worth on screen. **/
	public function scale():Float
		return Math.sqrt(Math.abs(a * d - b * c));

	public function isIdentity():Bool
		return a == 1 && b == 0 && c == 0 && d == 1 && e == 0 && f == 0;
}
