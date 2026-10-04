package ashui.draw;

/** How an open line ends: flat at its end, round, or squared off half its width past it. **/
enum abstract LineCap(Int) {
	var Butt = 0;
	var Round = 1;
	var Square = 2;
}

/** How a line turns a corner: to a point, round, or cut across. **/
enum abstract LineJoin(Int) {
	var Miter = 0;
	var Round = 1;
	var Bevel = 2;
}

/** How a path is outlined: its width, ends, corners and dashes. **/
class Stroke {
	public var width:Float;
	public var cap:LineCap;
	public var join:LineJoin;

	/** How long a miter may be, in widths, before the corner is cut across instead. **/
	public var miterLimit:Float;

	/** Lengths of dash and gap in turn, in the path's units; empty for a solid line. **/
	public var dash:Array<Float>;

	/** How far into the dash pattern the line starts. **/
	public var dashOffset:Float;

	public function new(width = 1.0, ?cap:LineCap, ?join:LineJoin, miterLimit = 4.0, ?dash:Array<Float>, dashOffset = 0.0) {
		this.width = width;
		this.cap = cap == null ? Butt : cap;
		this.join = join == null ? Miter : join;
		this.miterLimit = miterLimit;
		this.dash = dash == null ? [] : dash;
		this.dashOffset = dashOffset;
	}
}
