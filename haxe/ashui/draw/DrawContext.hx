package ashui.draw;

import ashui.draw.Path.FillRule;
import ashui.types.Brush;

/** One draw a context records: a path filled or stroked, with the transform, opacity and clip current when it was drawn. **/
enum DrawOp {
	Fill(path:Path, brush:Brush, rule:FillRule, transform:Affine, opacity:Float, clip:Null<DrawClip>);
	Stroke(path:Path, stroke:Stroke, brush:Brush, transform:Affine, opacity:Float, clip:Null<DrawClip>);

	/** A bitmap, the renderer's `slot`, drawn into the rect `x`, `y`, `width` by `height`. **/
	Image(slot:Int, x:Float, y:Float, width:Float, height:Float, transform:Affine, opacity:Float, clip:Null<DrawClip>);
}

/** What a clip keeps: a rectangle with its corners rounded by `radius`, or an ellipse, by its centre and half its width and height. **/
enum ClipShape {
	Box(x:Float, y:Float, width:Float, height:Float, radius:Float);
	Ellipse(cx:Float, cy:Float, rx:Float, ry:Float);
}

/**
	A clip pushed on a context: its shape, in the coordinates of the
	`transform` current when it was pushed, inside the clips pushed
	before it (`outer`). A draw is kept where it is inside all of them,
	its edge antialiased.
**/
class DrawClip {
	public final shape:ClipShape;
	public final transform:Affine;
	public final outer:Null<DrawClip>;

	/** How many clips, this one and those outside it. **/
	public final depth:Int;

	public function new(shape:ClipShape, transform:Affine, outer:Null<DrawClip>) {
		this.shape = shape;
		this.transform = transform;
		this.outer = outer;
		depth = outer == null ? 1 : outer.depth + 1;
	}
}

/** What an image is drawn from: a bitmap, `ashui.types.Bitmap`, which these are. **/
typedef DrawImage = {final slot:Int; final width:Int; final height:Int;}

/**
	What a canvas draws with: shapes and paths, filled or stroked with a
	`Brush`, under a stack of transforms and a stack of opacities, drawn
	in the order they are called, each over the last. Coordinates are the
	canvas's own, its content box's top-left at the origin, `width` by
	`height`, in layout units.

	Clips nest the same way: `pushClipRect`, `pushClipCircle` and
	`pushClipEllipse` keep what is drawn after them inside a shape,
	inside the clips already pushed, until the matching `popClip`.

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
	var clip:Null<DrawClip> = null;
	final clips:Array<Null<DrawClip>> = [];

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

	/** Draws after this kept inside the rectangle, its corners rounded by `radius`, until the matching `popClip`. **/
	public function pushClipRect(x:Float, y:Float, width:Float, height:Float, radius = 0.0):Void
		pushClip(Box(x, y, width, height, Math.max(0, Math.min(radius, Math.min(width, height) / 2))));

	/** Draws after this kept inside the circle, until the matching `popClip`. **/
	public function pushClipCircle(cx:Float, cy:Float, radius:Float):Void
		pushClip(Ellipse(cx, cy, radius, radius));

	/** Draws after this kept inside the ellipse, until the matching `popClip`. **/
	public function pushClipEllipse(cx:Float, cy:Float, rx:Float, ry:Float):Void
		pushClip(Ellipse(cx, cy, rx, ry));

	/** Draws after this kept inside `shape`, in the coordinates drawn in now, and inside the clips already pushed. **/
	public function pushClip(shape:ClipShape):Void {
		clips.push(clip);
		clip = new DrawClip(shape, transform, clip);
	}

	public function popClip():Void
		if (clips.length > 0)
			clip = clips.pop();

	/** The innermost clip pushed, the others through its `outer`; null when there are none. **/
	public function currentClip():Null<DrawClip>
		return clip;

	public function fillPath(path:Path, brush:Brush, ?rule:FillRule):Void
		ops.push(Fill(path, brush, rule == null ? NonZero : rule, transform, opacity, clip));

	public function strokePath(path:Path, stroke:Stroke, brush:Brush):Void
		ops.push(Stroke(path, stroke, brush, transform, opacity, clip));

	/** A rectangle, its corners rounded by `radius`. **/
	public function fillRect(x:Float, y:Float, width:Float, height:Float, brush:Brush, radius = 0.0):Void
		fillPath(new Path().roundedRect(x, y, width, height, radius), brush);

	public function strokeRect(x:Float, y:Float, width:Float, height:Float, stroke:Stroke, brush:Brush, radius = 0.0):Void
		strokePath(new Path().roundedRect(x, y, width, height, radius), stroke, brush);

	public function fillCircle(cx:Float, cy:Float, radius:Float, brush:Brush):Void
		fillPath(new Path().circle(cx, cy, radius), brush);

	public function strokeCircle(cx:Float, cy:Float, radius:Float, stroke:Stroke, brush:Brush):Void
		strokePath(new Path().circle(cx, cy, radius), stroke, brush);

	/**
		`text` filled with `brush`, set as `style` says, its point at `(x, y)`:
		where its start, middle or end is by `style.align`, and which of its
		lines is there by `style.baseline`, the baseline by default. Its
		glyphs are paths, so it scales and turns as any shape does. Lines
		break at `\n`. Draws nothing where there is no text engine.
	**/
	public function text(text:String, x:Float, y:Float, brush:Brush, ?style:GlyphOutlines.TextStyle):Void {
		var s:GlyphOutlines.TextStyle = style != null ? style : {};
		var outline = GlyphOutlines.of(text, s);
		if (outline == null || outline.commands.length == 0)
			return;
		var dx = switch s.align {
			case Middle: -outline.width / 2;
			case End: -outline.width;
			case _: 0.0;
		}
		var dy = switch s.baseline {
			case Top: outline.ascent;
			case Middle: (outline.ascent - outline.descent) / 2;
			case Bottom: -outline.descent;
			case _: 0.0;
		}
		fillPath(GlyphOutlines.path(outline, x + dx, y + dy), brush, NonZero);
	}

	/** How wide `text` set as `style` is, and how far it reaches above and below its baseline; zeros where there is no text engine. **/
	public function measureText(text:String, ?style:GlyphOutlines.TextStyle):{width:Float, ascent:Float, descent:Float} {
		var outline = GlyphOutlines.of(text, style != null ? style : {});
		return outline == null ? {width: 0.0, ascent: 0.0, descent: 0.0} : {width: outline.width, ascent: outline.ascent, descent: outline.descent};
	}

	/**
		`image` drawn into the rect at `(x, y)`, `width` by `height`, its own
		size when they are left out. It is resampled at the size it covers on
		screen, so it stays sharp up to its own resolution, turned or scaled.
	**/
	public function image(image:DrawImage, x:Float, y:Float, ?width:Float, ?height:Float):Void
		ops.push(Image(image.slot, x, y, width != null ? width : image.width, height != null ? height : image.height, transform, opacity, clip));

	/** A straight line, which has no inside: only its stroke. **/
	public function line(x1:Float, y1:Float, x2:Float, y2:Float, stroke:Stroke, brush:Brush):Void
		strokePath(new Path().moveTo(x1, y1).lineTo(x2, y2), stroke, brush);
}
