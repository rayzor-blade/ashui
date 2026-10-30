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

/**
	What a line's width follows when the shape it outlines is scaled: `Normal` scales it with the shape, `None` keeps it as
	drawn in the canvas's own units, `Horizontal` and `Vertical` follow only the shape's scale along that axis.
	A line's width stays the same all around, so a shape scaled unequally has one width, not two.
**/
enum abstract StrokeScale(Int) {
	var Normal = 0;
	var None = 1;
	var Horizontal = 2;
	var Vertical = 3;
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

	/** What the width follows when the shape is scaled. **/
	public var scaleMode:StrokeScale = Normal;

	/** Whether the line is one target pixel wide, whatever the scale; `width` is then not read. **/
	public var hairline = false;

	/** A line one target pixel wide, which scaling does not change. **/
	public static function onePixel(?cap:LineCap, ?join:LineJoin):Stroke {
		var s = new Stroke(1, cap, join);
		s.hairline = true;
		return s;
	}

	public function new(width = 1.0, ?cap:LineCap, ?join:LineJoin, miterLimit = 4.0, ?dash:Array<Float>, dashOffset = 0.0) {
		this.width = width;
		this.cap = cap == null ? Butt : cap;
		this.join = join == null ? Miter : join;
		this.miterLimit = miterLimit;
		this.dash = dash == null ? [] : dash;
		this.dashOffset = dashOffset;
	}

	/** Whether `other` strokes the same way: the same width and how it scales, caps, joins, miter limit and dashes. **/
	public function same(other:Null<Stroke>):Bool {
		if (other == this)
			return true;
		if (other == null || width != other.width || cap != other.cap || join != other.join || miterLimit != other.miterLimit
			|| dashOffset != other.dashOffset || dash.length != other.dash.length || scaleMode != other.scaleMode || hairline != other.hairline)
			return false;
		for (i in 0...dash.length)
			if (dash[i] != other.dash[i])
				return false;
		return true;
	}
}
