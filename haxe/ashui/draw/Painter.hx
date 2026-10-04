package ashui.draw;

import ashui.types.Brush;

/**
	Drawing with a current fill and stroke, as Processing does: set them,
	then draw shapes that take them. `fill` and `stroke` set them,
	`noFill` and `noStroke` leave them out; a shape is filled, then
	stroked, with whichever are set. `push` and `pop` bracket transforms:
	a `pop` undoes every `translate`, `rotate` and `scale` since its
	`push`, and the fill and stroke with them. Each call returns the
	painter, to chain.
**/
class Painter {
	public final ctx:DrawContext;

	var fillBrush:Null<Brush> = Brush.solid(0x000000);
	var strokeBrush:Null<Brush> = null;
	var strokeStyle = new Stroke(1);

	/** Per `push`: transforms pushed since, and the paint state to go back to. **/
	final groups:Array<{transforms:Int, fill:Null<Brush>, stroke:Null<Brush>, style:Stroke}> = [];

	public function new(ctx:DrawContext)
		this.ctx = ctx;

	public function fill(brush:Brush):Painter {
		fillBrush = brush;
		return this;
	}

	public function noFill():Painter {
		fillBrush = null;
		return this;
	}

	/** Strokes `width` wide, or with all of `style`'s caps, joins and dashes. **/
	public function stroke(brush:Brush, width = 1.0, ?style:Stroke):Painter {
		strokeBrush = brush;
		strokeStyle = style != null ? style : new Stroke(width, strokeStyle.cap, strokeStyle.join, strokeStyle.miterLimit);
		return this;
	}

	public function noStroke():Painter {
		strokeBrush = null;
		return this;
	}

	public function push():Painter {
		groups.push({transforms: 0, fill: fillBrush, stroke: strokeBrush, style: strokeStyle});
		return this;
	}

	public function pop():Painter {
		var g = groups.pop();
		if (g != null) {
			for (_ in 0...g.transforms)
				ctx.popTransform();
			fillBrush = g.fill;
			strokeBrush = g.stroke;
			strokeStyle = g.style;
		}
		return this;
	}

	public function translate(x:Float, y:Float):Painter
		return apply(Affine.translation(x, y));

	/** Turned by `radians` about the origin, clockwise on screen. **/
	public function rotate(radians:Float):Painter
		return apply(Affine.rotation(radians));

	public function scale(x:Float, ?y:Float):Painter
		return apply(Affine.scaling(x, y == null ? x : y));

	function apply(t:Affine):Painter {
		ctx.pushTransform(t);
		if (groups.length > 0)
			groups[groups.length - 1].transforms++;
		return this;
	}

	public function path(p:Path):Painter {
		if (fillBrush != null)
			ctx.fillPath(p, fillBrush);
		if (strokeBrush != null)
			ctx.strokePath(p, strokeStyle, strokeBrush);
		return this;
	}

	public function rect(x:Float, y:Float, w:Float, h:Float):Painter
		return path(new Path().rect(x, y, w, h));

	public function roundedRect(x:Float, y:Float, w:Float, h:Float, r:Float):Painter
		return path(new Path().roundedRect(x, y, w, h, r));

	public function circle(x:Float, y:Float, r:Float):Painter
		return path(new Path().circle(x, y, r));

	public function ellipse(x:Float, y:Float, rx:Float, ry:Float):Painter
		return path(new Path().ellipse(x, y, rx, ry));

	/** A line, which has no inside: only the stroke draws it. **/
	public function line(x1:Float, y1:Float, x2:Float, y2:Float):Painter {
		if (strokeBrush != null)
			ctx.strokePath(new Path().moveTo(x1, y1).lineTo(x2, y2), strokeStyle, strokeBrush);
		return this;
	}
}
