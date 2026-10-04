package ashui.types;

/** What one edge of a notch carries at its centre. **/
enum NotchEdge {
	None;
	/** A bowl carved in, `width` across and `depth` deep, its entry rounded by `radius` into ears, as the Dynamic Island's. **/
	Scoop(width:Float, depth:Float, ?radius:Float);
	/** An arc rising `height` out of the edge over `width`, its foot rounded by `radius`. **/
	Bulge(width:Float, height:Float, ?radius:Float);
	/** A V cut in, `width` across and `depth` deep. **/
	Cut(width:Float, depth:Float);
	/** A V rising `height` out of the edge over `width`, as a tooltip's arrow. **/
	Peak(width:Float, height:Float);
}

/**
	A shape a rounded box cannot make, drawn in place of the element's box:
	each corner's radius, negative for a concave corner that curves out to
	the element's edge, as a macOS menu-bar dropdown meets its bar, and a
	modifier at the centre of the top and bottom edges. Concave corners and
	outward modifiers lie inside the element's box: the body is inset by
	them, so give the element padding for its content. Signed radii can be
	animated through zero, from convex to concave. Ported from Blinc's
	`notch()`.
**/
@:structInit
class Notch {
	public final topLeft:Float;
	public final topRight:Float;
	public final bottomRight:Float;
	public final bottomLeft:Float;
	public final top:NotchEdge;
	public final bottom:NotchEdge;

	public function new(topLeft = 0.0, topRight = 0.0, bottomRight = 0.0, bottomLeft = 0.0, ?top:NotchEdge, ?bottom:NotchEdge) {
		this.topLeft = topLeft;
		this.topRight = topRight;
		this.bottomRight = bottomRight;
		this.bottomLeft = bottomLeft;
		this.top = top == null ? None : top;
		this.bottom = bottom == null ? None : bottom;
	}

	/** Concave top corners of `radius`, flaring to meet what is above, and round bottom corners of `bottomRadius`: the menu-bar dropdown. **/
	public static function concaveTop(radius:Float, bottomRadius = 0.0):Notch
		return new Notch(-radius, -radius, bottomRadius, bottomRadius);

	/** The twelve floats the renderer reads: the radii, then each edge as kind, width, height, radius. **/
	public function encode():Array<Single> {
		function edge(e:NotchEdge):Array<Single> {
			var v:Array<Float> = switch e {
				case None: [0, 0, 0, 0];
				case Scoop(w, d, r): [1, w, d, r == null ? 0.0 : (r : Float)];
				case Bulge(w, h, r): [2, w, h, r == null ? 0.0 : (r : Float)];
				case Cut(w, d): [3, w, d, 0];
				case Peak(w, h): [4, w, h, 0];
			}
			return [for (x in v) (x : Single)];
		}
		return ([topLeft, topRight, bottomRight, bottomLeft] : Array<Single>).concat(edge(top)).concat(edge(bottom));
	}
}
