package ashui.draw;

import ashui.draw.Path.FillRule;
import ashui.types.Brush;

/** One draw a context records: a path filled or stroked, with the transform and opacity current when it was drawn. **/
enum DrawOp {
	Fill(path:Path, brush:Brush, rule:FillRule, transform:Affine, opacity:Float);
	Stroke(path:Path, stroke:Stroke, brush:Brush, transform:Affine, opacity:Float);
}

/**
	What a canvas draws with: shapes and paths, filled or stroked with a
	`Brush`, under a stack of transforms and a stack of opacities, drawn
	in the order they are called, each over the last. Coordinates are the
	canvas's own, its content box's top-left at the origin, `width` by
	`height`, in layout units.

	It records rather than draws: the canvas plays its record on the GPU,
	at whatever size and place on screen it is drawn, so a path is
	flattened for the scale it is seen at.
**/
class DrawContext {
	public final width:Float;
	public final height:Float;

	/** The draws, in order. **/
	public final ops:Array<DrawOp> = [];

	var transform = Affine.IDENTITY;
	final transforms:Array<Affine> = [];
	var opacity = 1.0;
	final opacities:Array<Float> = [];

	public function new(width:Float, height:Float) {
		this.width = width;
		this.height = height;
	}

	/** Draws after this through `t` too, inside the transforms already pushed, until the matching `popTransform`. **/
	public function pushTransform(t:Affine):Void {
		transforms.push(transform);
		transform = transform.after(t);
	}

	public function popTransform():Void
		if (transforms.length > 0)
			transform = transforms.pop();

	/** The transforms pushed, together: from the coordinates drawn in now to the canvas's. **/
	public function currentTransform():Affine
		return transform;

	/** Draws after this at `alpha` times the opacity already pushed, until the matching `popOpacity`. **/
	public function pushOpacity(alpha:Float):Void {
		opacities.push(opacity);
		opacity *= alpha;
	}

	public function popOpacity():Void
		if (opacities.length > 0)
			opacity = opacities.pop();

	public function fillPath(path:Path, brush:Brush, ?rule:FillRule):Void
		ops.push(Fill(path, brush, rule == null ? NonZero : rule, transform, opacity));

	public function strokePath(path:Path, stroke:Stroke, brush:Brush):Void
		ops.push(Stroke(path, stroke, brush, transform, opacity));

	/** A rectangle, its corners rounded by `radius`. **/
	public function fillRect(x:Float, y:Float, width:Float, height:Float, brush:Brush, radius = 0.0):Void
		fillPath(new Path().roundedRect(x, y, width, height, radius), brush);

	public function strokeRect(x:Float, y:Float, width:Float, height:Float, stroke:Stroke, brush:Brush, radius = 0.0):Void
		strokePath(new Path().roundedRect(x, y, width, height, radius), stroke, brush);

	public function fillCircle(cx:Float, cy:Float, radius:Float, brush:Brush):Void
		fillPath(new Path().circle(cx, cy, radius), brush);

	public function strokeCircle(cx:Float, cy:Float, radius:Float, stroke:Stroke, brush:Brush):Void
		strokePath(new Path().circle(cx, cy, radius), stroke, brush);

	/** A straight line, which has no inside: only its stroke. **/
	public function line(x1:Float, y1:Float, x2:Float, y2:Float, stroke:Stroke, brush:Brush):Void
		strokePath(new Path().moveTo(x1, y1).lineTo(x2, y2), stroke, brush);
}
