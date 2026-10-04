package ashui.draw;

/**
	Triangles to draw, three vertices each, a vertex its position and its
	coverage: 1 inside a shape, falling to 0 across the pixel-wide fringe
	at its edge, which is how the shape is antialiased.
**/
class Mesh {
	/** `x, y, coverage` for each vertex. **/
	public final data:Array<Float> = [];

	public function new() {}

	public inline function vertexCount():Int
		return Std.int(data.length / 3);

	public inline function clear():Void
		data.resize(0);

	public inline function triangle(ax:Float, ay:Float, ac:Float, bx:Float, by:Float, bc:Float, cx:Float, cy:Float, cc:Float):Void {
		data.push(ax);
		data.push(ay);
		data.push(ac);
		data.push(bx);
		data.push(by);
		data.push(bc);
		data.push(cx);
		data.push(cy);
		data.push(cc);
	}

	/** The quad `a b c d`, in order around it, as two triangles. **/
	public inline function quad(ax:Float, ay:Float, ac:Float, bx:Float, by:Float, bc:Float, cx:Float, cy:Float, cc:Float, dx:Float, dy:Float,
			dc:Float):Void {
		triangle(ax, ay, ac, bx, by, bc, cx, cy, cc);
		triangle(ax, ay, ac, cx, cy, cc, dx, dy, dc);
	}
}
