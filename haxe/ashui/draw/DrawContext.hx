package ashui.draw;

import ashui.draw.Path.FillRule;
import ashui.types.Brush;

/** One draw a context records: a path filled or stroked, with the transform, opacity and clip current when it was drawn. **/
enum DrawOp {
	Fill(path:Path, brush:Brush, rule:FillRule, transform:Affine, opacity:Float, clip:Null<DrawClip>);
	Stroke(path:Path, stroke:Stroke, brush:Brush, transform:Affine, opacity:Float, clip:Null<DrawClip>);

	/** A bitmap, the renderer's `slot`, drawn into the rect `x`, `y`, `width` by `height`. **/
	Image(slot:Int, x:Float, y:Float, width:Float, height:Float, transform:Affine, opacity:Float, clip:Null<DrawClip>);

	/** A mesh in 3D, placed by `transform`, seen as `scene` says. **/
	Mesh3D(mesh:ashui.draw3d.MeshData, transform:ashui.math.Mat4, scene:ashui.draw3d.Scene3D, opacity:Float, material:ashui.draw3d.Material);

	/** Drawing of one's own in the same 3D scene (see `ashui.draw3d.ScenePass`). **/
	Pass3D(pass:ashui.draw3d.ScenePass, scene:ashui.draw3d.Scene3D);

	/** A batch of triangles textured from a bitmap, placed by `transform`. **/
	Textured(batch:TexturedBatch, transform:Affine, opacity:Float, clip:Null<DrawClip>);

	/** The blend mode of the draws after it, until the next one. **/
	Blend(mode:BlendMode);

	/** The colour transform of the draws after it, until the next one. **/
	Tint(transform:ColorTransform);

	/** The draws up to `MaskUse` make a mask rather than appear; those after it are kept where it is drawn, until `MaskEnd`. **/
	MaskBegin;

	MaskUse;
	MaskEnd;
}

/** Which triangles `drawTriangles` leaves out, by the winding of their vertices on the canvas: clockwise on screen is positive. **/
enum abstract TriangleCulling(Int) {
	var None = 0;

	/** Leaves out those wound clockwise. **/
	var Positive = 1;

	/** Leaves out those wound counterclockwise. **/
	var Negative = 2;
}

/**
	Triangles textured from one bitmap: `positions` and `uvs` are x, y pairs, `group` vertices to a group; a group is one
	paint, mapped from its first three vertices, so a quad's six vertices are one group. A group has its own alpha and
	colour transform when `alphas` and `tints` have them.
**/
typedef TexturedBatch = {
	final slot:Int;
	final width:Int;
	final height:Int;
	final positions:Array<Float>;
	final uvs:Array<Float>;
	final group:Int;
	final alphas:Null<Array<Float>>;
	final tints:Null<Array<ColorTransform>>;
	final smooth:Bool;
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

/** What an image is drawn from: a bitmap, `ashui.types.Bitmap`, whose `slot` is read when it is drawn (a bitmap not decoded yet decodes then). **/
typedef DrawImage = {var slot(get, never):Int; var width(default, null):Int; var height(default, null):Int;}

/**
	What a canvas draws with: shapes and paths, filled or stroked with a
	`Brush`, under a stack of transforms and a stack of opacities, drawn
	in the order they are called, each over the last. Coordinates are the
	canvas's own, its content box's top-left at the origin, `width` by
	`height`, in layout units.

	Clips nest the same way: `pushClipRect`, `pushClipCircle` and
	`pushClipEllipse` keep what is drawn after them inside a shape,
	inside the clips already pushed, until the matching `popClip`.

	Meshes are drawn in 3D with `drawMesh`, seen through the camera and lit
	by the lights `setCamera`, `setLights` or `setScene` set last, and one's
	own GPU drawing joins them with `drawPass`. Meshes and passes drawn one
	after another share a depth buffer, nearer surfaces hiding
	further ones, over the canvas's box; shapes drawn after them go over
	them. A mesh takes the canvas's clipping and the opacity pushed, not
	the clips pushed.

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
	var blend = BlendMode.Normal;
	final blends:Array<BlendMode> = [];
	var tint = ColorTransform.IDENTITY;
	final tints:Array<ColorTransform> = [];
	var maskDepth = 0;
	var scene = ashui.draw3d.Scene3D.DEFAULT;
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

	/** Draws after this combined with what is under them as `mode` says, until the matching `popBlendMode`; shapes and images only. **/
	public function pushBlendMode(mode:BlendMode):Void {
		blends.push(blend);
		blend = mode;
		ops.push(Blend(mode));
	}

	public function popBlendMode():Void
		if (blends.length > 0) {
			blend = blends.pop();
			ops.push(Blend(blend));
		}

	/** Draws after this with their colours changed by `t` and then by the transforms already pushed, until the matching `popColorTransform`; shapes and images only. **/
	public function pushColorTransform(t:ColorTransform):Void {
		tints.push(tint);
		tint = tint.after(t);
		ops.push(Tint(tint));
	}

	public function popColorTransform():Void
		if (tints.length > 0) {
			tint = tints.pop();
			ops.push(Tint(tint));
		}

	/**
		Draws after this kept where `mask` draws, by the alpha of what it draws, until the matching `popMask`. `mask` is called
		now, with this context, and draws as any shape does, under the transforms and opacity pushed; its blend modes and colour
		transforms are ignored. Masks do not nest: one pushed inside another is not applied. Shapes and images only.
	**/
	public function pushMask(mask:DrawContext->Void):Void {
		if (maskDepth++ > 0)
			return;
		ops.push(MaskBegin);
		mask(this);
		ops.push(MaskUse);
	}

	public function popMask():Void {
		if (maskDepth > 0 && --maskDepth == 0)
			ops.push(MaskEnd);
	}

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

	/** `path` filled with `fill` by `rule`, then outlined with `stroke` in `strokeBrush`; either is left out where it is null. **/
	public function drawPath(path:Path, ?fill:Brush, ?rule:FillRule, ?stroke:Stroke, ?strokeBrush:Brush):Void {
		if (fill != null)
			fillPath(path, fill, rule);
		if (stroke != null && strokeBrush != null)
			strokePath(path, stroke, strokeBrush);
	}

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
		pushTransform(new Affine(1, 0, 0, 1, x + dx, y + dy));
		fillPath(GlyphOutlines.shape(outline), brush, NonZero);
		popTransform();
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

	/** What meshes drawn after this are seen through: its camera, lighting, exposure and background. **/
	public function setScene(scene:ashui.draw3d.Scene3D):Void
		this.scene = scene;

	public function currentScene():ashui.draw3d.Scene3D
		return scene;

	/** Meshes drawn after this seen through `camera`. **/
	public function setCamera(camera:ashui.draw3d.Camera):Void
		scene = scene.with(camera);

	/** Meshes drawn after this lit by `lights` and a little ambient light (`BasicLighting`). **/
	public function setLights(lights:Array<ashui.draw3d.Light>):Void
		scene = scene.with(null, new ashui.draw3d.SceneLighting.BasicLighting(lights));

	/** Meshes drawn after this lit by `lighting`. **/
	public function setLighting(lighting:ashui.draw3d.SceneLighting):Void
		scene = scene.with(null, lighting);

	/**
		`pass` drawn in 3D with the meshes drawn around it, sharing their
		depth: one's own GPU drawing in the scene (see `ScenePass`).
	**/
	public function drawPass(pass:ashui.draw3d.ScenePass):Void
		ops.push(Pass3D(pass, scene));

	/**
		`mesh` drawn in 3D, placed by `transform`, the identity by default, in
		`material`, its own by default: one mesh on the GPU drawn in several
		materials, or in one that changes, is uploaded once.
	**/
	public function drawMesh(mesh:ashui.draw3d.MeshData, ?transform:ashui.math.Mat4, ?material:ashui.draw3d.Material):Void
		ops.push(Mesh3D(mesh, transform != null ? transform : ashui.math.Mat4.IDENTITY, scene, opacity, material != null ? material : mesh.material));

	/**
		Triangles of `vertices`, x, y pairs, drawn by `indices`, three to a triangle, or in order where there are none, textured from
		`image` by `uvs`, u, v pairs from 0 to 1 across it, one pair to a vertex; `smooth` filters between its pixels. Where `image`
		is null they are filled with `brush`. A texture's coordinates are mapped linearly across each triangle, and the edges are
		not antialiased.
	**/
	public function drawTriangles(vertices:Array<Float>, ?indices:Array<Int>, ?uvs:Array<Float>, ?image:DrawImage, ?brush:Brush, ?culling:TriangleCulling,
			smooth = false):Void {
		var count = indices == null ? Std.int(vertices.length / 2) : indices.length;
		var positions:Array<Float> = [], coords:Array<Float> = [];
		var i = 0;
		while (i + 2 < count) {
			var v = [for (k in 0...3) indices == null ? i + k : indices[i + k]];
			i += 3;
			var ax = vertices[v[0] * 2], ay = vertices[v[0] * 2 + 1];
			var bx = vertices[v[1] * 2], by = vertices[v[1] * 2 + 1];
			var cx = vertices[v[2] * 2], cy = vertices[v[2] * 2 + 1];
			var winding = (bx - ax) * (cy - ay) - (by - ay) * (cx - ax);
			if (culling == Positive && winding > 0 || culling == Negative && winding < 0)
				continue;
			if (image == null || uvs == null) {
				if (brush != null)
					fillPath(new Path().moveTo(ax, ay).lineTo(bx, by).lineTo(cx, cy).close(), brush);
				continue;
			}
			for (k in v) {
				positions.push(vertices[k * 2]);
				positions.push(vertices[k * 2 + 1]);
				coords.push(uvs[k * 2]);
				coords.push(uvs[k * 2 + 1]);
			}
		}
		if (positions.length > 0)
			ops.push(Textured({
				slot: image.slot,
				width: image.width,
				height: image.height,
				positions: positions,
				uvs: coords,
				group: 3,
				alphas: null,
				tints: null,
				smooth: smooth
			}, transform, opacity, clip));
	}

	/**
		Many quads of `image` in one draw, as a tile map draws them. Each takes the rectangle of `image` that starts at its
		`rects` entry, four numbers `x, y, width, height` in the image's pixels, and draws it at the origin as large as it is,
		placed by its `transforms` entry, six numbers `a, b, c, d, tx, ty` as an `Affine` has them. `alphas` and `tints`, where
		given, have one entry for each quad. `smooth` filters between the image's pixels. The edges are not antialiased.
	**/
	public function drawQuads(image:DrawImage, rects:Array<Float>, transforms:Array<Float>, ?alphas:Array<Float>, ?tints:Array<ColorTransform>,
			smooth = false):Void {
		var n = Std.int(Math.min(rects.length / 4, transforms.length / 6));
		var positions:Array<Float> = [], coords:Array<Float> = [];
		var w = image.width, h = image.height;
		for (q in 0...n) {
			var sx = rects[q * 4], sy = rects[q * 4 + 1], sw = rects[q * 4 + 2], sh = rects[q * 4 + 3];
			var a = transforms[q * 6], b = transforms[q * 6 + 1], c = transforms[q * 6 + 2], d = transforms[q * 6 + 3], e = transforms[q * 6 + 4],
				f = transforms[q * 6 + 5];
			// The corners in order, the quad's two triangles from them.
			var cx = [0.0, sw, sw, 0.0], cy = [0.0, 0.0, sh, sh];
			for (k in [0, 1, 2, 0, 2, 3]) {
				positions.push(a * cx[k] + c * cy[k] + e);
				positions.push(b * cx[k] + d * cy[k] + f);
				coords.push((sx + cx[k]) / w);
				coords.push((sy + cy[k]) / h);
			}
		}
		if (n > 0)
			ops.push(Textured({
				slot: image.slot,
				width: w,
				height: h,
				positions: positions,
				uvs: coords,
				group: 6,
				alphas: alphas,
				tints: tints,
				smooth: smooth
			}, transform, opacity, clip));
	}

	/**
		`image` stretched into the rect at `(x, y)`, `width` by `height`, in nine parts, as a nine-slice or `scale9Grid` is: its
		corners keep their size, its edges stretch along themselves, and its middle stretches both ways. `left`, `top`, `right`
		and `bottom` are the corners' sizes in the image's pixels. A rect smaller than the corners squeezes them.
	**/
	public function image9(image:DrawImage, x:Float, y:Float, width:Float, height:Float, left:Float, top:Float, right:Float, bottom:Float, smooth = false):Void {
		var iw = image.width, ih = image.height;
		// Corners that do not fit in the rect share it.
		var fit = Math.min(1, width / Math.max(left + right, 1e-9)), fitY = Math.min(1, height / Math.max(top + bottom, 1e-9));
		var dl = left * fit, dr = right * fit, dt = top * fitY, db = bottom * fitY;
		var sx = [0.0, left, iw - right, iw], sy = [0.0, top, ih - bottom, ih];
		var dx = [0.0, dl, width - dr, width], dy = [0.0, dt, height - db, height];
		var rects:Array<Float> = [], transforms:Array<Float> = [];
		for (j in 0...3)
			for (i in 0...3) {
				var sw = sx[i + 1] - sx[i], sh = sy[j + 1] - sy[j], tw = dx[i + 1] - dx[i], th = dy[j + 1] - dy[j];
				if (sw <= 0 || sh <= 0 || tw <= 0 || th <= 0)
					continue;
				rects.push(sx[i]);
				rects.push(sy[j]);
				rects.push(sw);
				rects.push(sh);
				transforms.push(tw / sw);
				transforms.push(0);
				transforms.push(0);
				transforms.push(th / sh);
				transforms.push(x + dx[i]);
				transforms.push(y + dy[j]);
			}
		drawQuads(image, rects, transforms, null, null, smooth);
	}

	/** A straight line, which has no inside: only its stroke. **/
	public function line(x1:Float, y1:Float, x2:Float, y2:Float, stroke:Stroke, brush:Brush):Void
		strokePath(new Path().moveTo(x1, y1).lineTo(x2, y2), stroke, brush);
}
