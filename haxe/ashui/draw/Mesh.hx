package ashui.draw;

/**
	Triangles to draw, three vertices each. A vertex is its position, its
	coverage, and its distances, in target pixels, inside each of up to
	four of the shape's edges near it.

	Coverage is 1 inside a shape and falls to 0 across the fringe outside
	its edge. The distances, which change evenly across a triangle as a
	distance to a straight line does, let a pixel inside the edge be
	covered by how far inside it is: together, a pixel is covered as much
	as it is in the shape, on both sides of the edge. `FAR` is no edge.
**/
class Mesh {
	/** Values to a vertex: `x, y, coverage`, then the four distances. **/
	public static inline var STRIDE = 7;

	/** A distance that leaves a pixel fully covered: no edge near. **/
	public static inline var FAR = 1e6;

	public final data:Array<Float> = [];

	public function new() {}

	public inline function vertexCount():Int
		return Std.int(data.length / STRIDE);

	public inline function clear():Void
		data.resize(0);

	public inline function vertex(x:Float, y:Float, c:Float, d0:Float = FAR, d1:Float = FAR, d2:Float = FAR, d3:Float = FAR):Void {
		data.push(x);
		data.push(y);
		data.push(c);
		data.push(d0);
		data.push(d1);
		data.push(d2);
		data.push(d3);
	}

	public inline function triangle(ax:Float, ay:Float, ac:Float, bx:Float, by:Float, bc:Float, cx:Float, cy:Float, cc:Float):Void {
		vertex(ax, ay, ac);
		vertex(bx, by, bc);
		vertex(cx, cy, cc);
	}

	/** The quad `a b c d`, in order around it, as two triangles. **/
	public inline function quad(ax:Float, ay:Float, ac:Float, bx:Float, by:Float, bc:Float, cx:Float, cy:Float, cc:Float, dx:Float, dy:Float,
			dc:Float):Void {
		triangle(ax, ay, ac, bx, by, bc, cx, cy, cc);
		triangle(ax, ay, ac, cx, cy, cc, dx, dy, dc);
	}
}
