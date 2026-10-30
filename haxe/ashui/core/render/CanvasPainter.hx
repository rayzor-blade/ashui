package ashui.core.render;

import ashui.draw.Affine;
import ashui.draw.BlendMode;
import ashui.draw.ColorTransform;
import ashui.draw.DrawContext;
import ashui.draw.Flatten;
import ashui.draw.Mesh;
import ashui.draw.Path.FillRule;
import ashui.draw.Tessellate;
import ashui.types.Brush;
import gpu.GpuBindGroup;
import gpu.GpuBindings;
import gpu.GpuExtent3D;
import gpu.GpuPipeline;
import gpu.GpuTexture;
import gpu.GpuTextureDescriptor;
import gpu.GpuTextureView;
import gpu.GpuTextureViewDescriptor;
import gpu.TextureFormat;

/**
	Plays a canvas's `DrawContext` on the GPU: each draw's path flattened
	and tessellated in layout units for where the canvas is on screen, a
	target pixel wide fringe at its edges, its paint after the vertices in
	the canvas's data texture, all drawn in one call of `PathShader` in the
	order they were drawn. The triangles are made again only when the
	record, the canvas's transform or its scale changes.
**/
class CanvasPainter {
	/** Off screen by less than a quarter of a target pixel, which is all a flattened curve strays. **/
	static inline var TOLERANCE = 0.25;

	var texture:Null<GpuTexture> = null;
	var view:Null<GpuTextureView> = null;
	var rows = 0;
	/** The data's bind group for each blend mode's pipeline, and the pipeline each was made for. **/
	final groups:Array<Null<GpuBindGroup>> = [for (_ in 0...BlendMode.COUNT) null];

	final groupPipelines:Array<Null<GpuPipeline>> = [for (_ in 0...BlendMode.COUNT) null];

	/** The group the pass that draws a mask uses, with no mask to read; and the mask view the others were made with. **/
	var maskPassGroup:Null<GpuBindGroup> = null;

	var groupMask:Null<GpuTextureView> = null;
	var vertexCount = 0;

	/** What the triangles were made for: the record, and the canvas's transform and pixel ratio. **/
	var madeFor:Null<DrawContext> = null;

	var madeTransform:Null<Affine> = null;
	var madeRatio = 0.0;

	/** The image atlas's revision the triangles' image rects are for; a reset of the atlas moves them. **/
	var madeAtlas = -1;

	var groupAtlas = -1;

	/** Kept from build to build: the triangles, where each draw's begin, the paints, and the bytes uploaded. **/
	final mesh = new Mesh();

	final starts:Array<Int> = [];
	final paints:Array<Float> = [];

	/** Per draw, the clip it was drawn under. **/
	final drawClips:Array<Null<DrawClip>> = [];

	/** The clip table: each clip once, in the order written, and the texel each starts at, from the table's start. **/
	final clipOrder:Array<DrawClip> = [];

	final clipAt = new haxe.ds.ObjectMap<DrawClip, Int>();

	/**
		Each path drawn last frame, and its triangles once it has been drawn twice: a path drawn again is moved, not tessellated
		again. A path is found again by what it contains, by its signature, so one made afresh each frame is the same path as the
		last frame's.
	**/
	final shapes = new haxe.ds.IntMap<Array<Shape>>();

	/** Signatures whose shapes were all forgotten in a build, to drop from `shapes`. **/
	final emptied:Array<Int> = [];

	/** The shape drawn from a path with `path`'s commands, if there is one. **/
	function shapeOf(path:ashui.draw.Path):Null<Shape> {
		var bucket = shapes.get(path.signature());
		if (bucket != null)
			for (known in bucket)
				if (ashui.draw.Path.same(known.path, path))
					return known;
		return null;
	}

	function keep(shape:Shape):Void {
		var sig = shape.path.signature();
		var bucket = shapes.get(sig);
		if (bucket == null)
			shapes.set(sig, bucket = []);
		bucket.push(shape);
	}

	/** Forgets what the last build did not draw. **/
	function forgetUnused():Void {
		for (sig => bucket in shapes) {
			var i = bucket.length;
			while (i-- > 0)
				if (bucket[i].build != builds)
					bucket.splice(i, 1);
			if (bucket.length == 0)
				emptied.push(sig);
		}
		for (sig in emptied)
			shapes.remove(sig);
		emptied.resize(0);
	}

	/** Counts builds, so a shape not drawn in the last one is forgotten. **/
	var builds = 0;

	var bytes:Null<haxe.io.Bytes> = null;

	/** How long after its last build a canvas keeps what it tessellated and uploaded, in seconds, for the next build to reuse. **/
	static inline var KEEP = 2.0;

	var releasing:Null<ashui.animation.AnimationScheduler.Timer> = null;

	/** Whether what a build left on the CPU is kept, not given back when the canvas has not been built for `KEEP` seconds. **/
	public var retain = false;

	/**
		Gives back what a build left on the CPU: the triangles, each path's copy, the bytes uploaded, and the lists of draws and
		clips. A canvas that redraws every frame keeps them, to build into again; one that has not been built for a while is only
		drawn from what is on the GPU, and these, which can be tens of megabytes for a detailed drawing, are of no use until the
		next build makes them again.
	**/
	function release():Void {
		releasing = null;
		mesh.release();
		shapes.clear();
		bytes = null;
		starts.resize(0);
		paints.resize(0);
		drawClips.resize(0);
		clipOrder.resize(0);
		clipAt.clear();
	}

	/** The record's runs, in order: of paths, by their vertices, and of meshes, each drawn by `scenes`. **/
	final steps:Array<CanvasStep> = [];

	var scenes:Null<ScenePainter> = null;

	/** Asks for the canvas to be drawn again; its 3D draws call it as their textures change. **/
	public var repaint:Void->Void = () -> {};

	/** Called as its 3D draws start or stop waiting for their textures. **/
	public var onLoading:Bool->Void = _ -> {};

	/** Called after each frame in which its 3D draws were rendered afresh. **/
	public var onSceneFrame:Void->Void = () -> {};

	public function new() {}

	var disposed = false;

	/** Frees what it built: its triangles and shapes, the data texture and bind group on the GPU, and what its 3D draws uploaded. It draws nothing after. **/
	public function dispose():Void {
		disposed = true;
		if (releasing != null)
			releasing.cancel();
		releasing = null;
		release();
		dropGroups();
		if (view != null) {
			view.destroy();
			view = null;
		}
		if (texture != null) {
			texture.destroy();
			texture = null;
		}
		madeFor = null;
		madeTransform = null;
		if (scenes != null) {
			scenes.dispose();
			scenes = null;
		}
	}

	function dropGroups():Void {
		for (i in 0...groups.length) {
			if (groups[i] != null)
				groups[i].destroy();
			groups[i] = null;
		}
		if (maskPassGroup != null)
			maskPassGroup.destroy();
		maskPassGroup = null;
	}

	/**
		Whether `play` would build again for `ctx` drawn through `t` at `ratio` pixels to a unit, with the image atlas at
		`atlasRevision`: whether what it draws is not what it drew last. A painter that is not built again draws the same.
	**/
	public function needsBuild(ctx:DrawContext, t:Affine, ratio:Float, atlasRevision:Int):Bool {
		if (disposed)
			return false;
		var m = madeTransform;
		return ctx != madeFor || m == null || t.a != m.a || t.b != m.b || t.c != m.c || t.d != m.d || t.e != m.e || t.f != m.f || ratio != madeRatio
			|| (hasImages && atlasRevision != madeAtlas);
	}

	/** Whether its 3D draws would be rendered again, as a scene with a pass that changes each frame is, or as one waiting for textures is as they come. **/
	public function sceneChanging():Bool {
		if (scenes == null)
			return false;
		for (step in steps)
			switch step {
				case Meshes(_, passes, _):
					for (p in passes)
						if (p.animated())
							return true;
				case _:
			}
		return scenes.pending();
	}

	public function play(frame:CanvasFrame, ctx:DrawContext):Void {
		if (disposed)
			return;
		var t = frame.transform, m = madeTransform;
		var moved = m == null || t.a != m.a || t.b != m.b || t.c != m.c || t.d != m.d || t.e != m.e || t.f != m.f;
		var atlas = frame.images;
		if (ctx != madeFor || moved || frame.pixelRatio != madeRatio || (hasImages && atlas.revision != madeAtlas)) {
			build(frame, ctx);
			madeFor = ctx;
			madeTransform = t;
			madeRatio = frame.pixelRatio;
			madeAtlas = atlas.revision;
		}
		for (step in steps)
			if (step.match(Meshes(_)) && scenes == null) {
				scenes = new ScenePainter(() -> repaint());
				scenes.onLoading = v -> onLoading(v);
				scenes.onRendered = () -> onSceneFrame();
			}
		if (scenes != null)
			scenes.beginFrame();
		var run = 0;
		for (step in steps)
			switch step {
				case Paths(first, count, blend):
					drawPaths(frame, first, count, blend);
				case Mask(first, count):
					drawMask(frame, first, count);
				case Meshes(draws, passes, scene):
					scenes.draw(frame, run++, draws, passes, scene);
			}
		if (scenes != null)
			scenes.endFrame();
	}

	function drawPaths(frame:CanvasFrame, first:Int, count:Int, blend:BlendMode):Void {
		var atlas = frame.images;
		var pipeline = frame.bindBlended(PathShader.WGSL, blend);
		var mode:Int = blend;
		var mask = frame.maskView();
		if (groupAtlas != atlas.revision || groupMask != mask)
			dropGroups();
		var group = groups[mode];
		if (group == null || groupPipelines[mode] != pipeline.pipeline) {
			if (group != null)
				group.destroy();
			groups[mode] = group = bindData(frame, pipeline.pipeline, mask);
			groupPipelines[mode] = pipeline.pipeline;
			groupAtlas = atlas.revision;
			groupMask = mask;
		}
		frame.encoder.renderSetBindGroup(PathShader.TEXTURE_canvas_GROUP, group);
		frame.encoder.renderDrawRange(count, 1, first, frame.record);
	}

	/** The image atlas and its sampler, the mask texture and its sampler, then the canvas's data, which is fetched, never sampled. **/
	function bindData(frame:CanvasFrame, pipeline:GpuPipeline, mask:GpuTextureView):GpuBindGroup {
		var bindings = new GpuBindings();
		bindings.texture(frame.images.view);
		bindings.sampler(frame.imageSampler);
		bindings.texture(mask);
		bindings.sampler(frame.imageSampler);
		bindings.texture(view);
		var made = frame.device.bindGroup(pipeline, PathShader.TEXTURE_canvas_GROUP, bindings);
		bindings.destroy();
		return made;
	}

	/** Draws a mask's `count` vertices from `first` into the mask texture, replacing what it held. **/
	function drawMask(frame:CanvasFrame, first:Int, count:Int):Void
		frame.drawMask(() -> {
			var pipeline = frame.bindBlended(PathShader.WGSL, Normal);
			if (maskPassGroup == null)
				maskPassGroup = bindData(frame, pipeline.pipeline, frame.noMaskView());
			frame.encoder.renderSetBindGroup(PathShader.TEXTURE_canvas_GROUP, maskPassGroup);
			if (count > 0)
				frame.encoder.renderDrawRange(count, 1, first, frame.record);
		});

	var warnedOverfull = false;

	/** Says once on stderr that the canvas's paths do not all fit the GPU's texture limit, and what is done about it. **/
	function overfull(what:String):Void {
		if (warnedOverfull)
			return;
		warnedOverfull = true;
		Sys.stderr().writeString('[ashui] a canvas has more triangles than the GPU holds in a texture, ${Renderer.maxTexture} rows of ${PathShader.ROW_TEXELS} texels; it $what\n');
	}

	function build(frame:CanvasFrame, ctx:DrawContext):Void {
		builds++;
		// A target pixel, in the layout units the triangles are in.
		var aa = 1 / frame.pixelRatio;
		var tolerance = TOLERANCE / frame.pixelRatio;
		mesh.clear();
		starts.resize(0);
		paints.resize(0);
		drawClips.resize(0);
		clipOrder.resize(0);
		clipAt.clear();
		steps.resize(0);
		hasImages = false;
		var pathsFrom = 0;
		var blend = BlendMode.Normal;
		var tint = ColorTransform.IDENTITY;
		// Inside a mask's draws, which are drawn into the mask texture as they are; after them, draws are kept by it.
		var inMask = false, masked = false, maskFrom = 0;
		function endPaths() {
			if (mesh.vertexCount() > pathsFrom)
				steps.push(Paths(pathsFrom, mesh.vertexCount() - pathsFrom, blend));
			pathsFrom = mesh.vertexCount();
		}
		// The table is one texture, so it has a device's limit of rows; a quarter of it is kept for the clips, and what comes after the rest is left out.
		var capacity = Renderer.maxTexture * PathShader.ROW_TEXELS;
		for (op in ctx.ops) {
			var before = mesh.vertexCount();
			if (before * PathShader.VERTEX_TEXELS + starts.length * PathShader.PAINT_TEXELS > capacity - (capacity >> 2)) {
				overfull("is drawn only in part");
				break;
			}
			switch op {
				case Blend(mode):
					// Each run of paths is drawn through the pipeline of the mode it was recorded under.
					if (!inMask) {
						endPaths();
						blend = mode;
					}
					continue;
				case Tint(t):
					if (!inMask)
						tint = t;
					continue;
				case MaskBegin:
					endPaths();
					inMask = true;
					maskFrom = mesh.vertexCount();
					continue;
				case MaskUse:
					// A mask with nothing drawn still clears the texture, so what is masked by it is hidden.
					steps.push(Mask(maskFrom, mesh.vertexCount() - maskFrom));
					pathsFrom = mesh.vertexCount();
					inMask = false;
					masked = true;
					continue;
				case MaskEnd:
					masked = false;
					continue;
				case Mesh3D(_, _, scene, _, _) | Pass3D(_, scene) if (inMask):
					continue;
				case Mesh3D(_, _, scene, _, _) | Pass3D(_, scene):
					endPaths();
					// Meshes and passes drawn one after another, seen the same way, are one run, sharing depth.
					var last = steps.length > 0 ? steps[steps.length - 1] : null;
					var run = switch last {
						case Meshes(draws, passes, s) if (last != null && s == scene): {draws: draws, passes: passes};
						case _:
							var made = {draws: [], passes: []};
							steps.push(Meshes(made.draws, made.passes, scene));
							made;
					}
					switch op {
						case Mesh3D(m, transform, _, opacity, material): run.draws.push({
								mesh: m,
								transform: transform,
								opacity: opacity,
								material: material
							});
						case Pass3D(pass, _): run.passes.push(pass);
						case _:
					}
					continue;
				case Fill(path, brush, rule, transform, opacity, clip):
					var m = frame.transform.after(transform);
					var contours = tessellate(path, m, tolerance, aa, rule, null, needsContours(brush));
					if (mesh.vertexCount() > before)
						encode(frame, brush, m, contours, opacity, paints, inMask ? ColorTransform.IDENTITY : tint, masked);
							case Stroke(path, stroke, brush, transform, opacity, clip):
					var m = frame.transform.after(transform);
					var contours = tessellate(path, m, tolerance, aa, NonZero, stroke, needsContours(brush));
					if (mesh.vertexCount() > before)
						encode(frame, brush, m, contours, opacity, paints, inMask ? ColorTransform.IDENTITY : tint, masked);
							case Image(slot, x, y, w, h, transform, opacity, clip):
					hasImages = true;
					var m = frame.transform.after(transform);
					var contours = Flatten.path(new ashui.draw.Path().rect(x, y, w, h), m, tolerance);
					Tessellate.fill(contours, NonZero, aa, mesh);
					if (mesh.vertexCount() > before)
						encodeImage(frame, slot, x, y, w, h, m, opacity, paints, inMask ? ColorTransform.IDENTITY : tint, masked);
			}
			if (mesh.vertexCount() > before) {
				starts.push(before);
				drawClips.push(clipOf(op));
			}
		}
		endPaths();
		forgetUnused();
		vertexCount = mesh.vertexCount();
		if (vertexCount == 0) {
			// With no vertices there is no data texture for a mask's draws to read.
			var i = steps.length;
			while (i-- > 0)
				if (steps[i].match(Mask(_, _)))
					steps.splice(i, 1);
			return;
		}
		var draws = starts.length;
		var table = vertexCount * PathShader.VERTEX_TEXELS + draws * PathShader.PAINT_TEXELS;
		// A paint's head ends with the texel its clip starts at, 0 for none: texel 0 is a vertex, never a clip.
		for (i in 0...draws) {
			var c = drawClips[i];
			if (c != null)
				paints[i * PathShader.PAINT_TEXELS * 4 + 3] = table + place(c);
		}
		var texels = table + clipOrder.length * PathShader.CLIP_TEXELS;
		var needed = Std.int(Math.ceil(texels / PathShader.ROW_TEXELS));
		if (needed > Renderer.maxTexture) {
			// Its clips took more than was kept for them: nothing of its paths is drawn.
			overfull("is not drawn");
			var i = steps.length;
			while (i-- > 0)
				if (steps[i].match(Paths(_, _, _) | Mask(_, _)))
					steps.splice(i, 1);
			vertexCount = 0;
			return;
		}
		var size = needed * PathShader.ROW_TEXELS * 16;
		if (bytes == null || bytes.length < size)
			bytes = haxe.io.Bytes.alloc(size + (size >> 1));
		var out = bytes, at = 0;
		inline function put(v:Float) {
			out.setFloat(at, v);
			at += 4;
		}
		var d = mesh.data;
		for (i in 0...draws) {
			var paintTexel = vertexCount * PathShader.VERTEX_TEXELS + i * PathShader.PAINT_TEXELS;
			var k = starts[i] * Mesh.STRIDE,
				end = (i + 1 < draws ? starts[i + 1] : vertexCount) * Mesh.STRIDE;
			while (k < end) {
				put(d[k]);
				put(d[k + 1]);
				put(d[k + 2]);
				put(paintTexel);
				for (j in 3...Mesh.STRIDE)
					put(d[k + j]);
				k += Mesh.STRIDE;
			}
		}
		for (v in paints)
			put(v);
		for (c in clipOrder)
			for (v in encodeClip(frame, c, c.outer == null ? 0 : table + clipAt.get(c.outer)))
				put(v);
		if (texture == null || needed > rows) {
			if (texture != null)
				texture.destroy();
			if (view != null)
				view.destroy();
			rows = Std.int(Math.min(needed + (needed >> 1), Renderer.maxTexture));
			var extent = new GpuExtent3D(PathShader.ROW_TEXELS);
			extent.height(rows);
			texture = frame.device.texture(new GpuTextureDescriptor(extent, TextureFormat.Rgba32float, GpuFlags.TEXTURE_BINDING | GpuFlags.TEXTURE_COPY_DST));
			view = texture.createView(new GpuTextureViewDescriptor());
			dropGroups();
		}
		frame.device.queue().writeTexture(texture, bytes, PathShader.ROW_TEXELS, needed, PathShader.ROW_TEXELS * 16);
		if (releasing != null)
			releasing.cancel();
		releasing = retain ? null : ashui.animation.AnimationScheduler.main.after(KEEP, release);
	}

	/** Whether the record draws an image, so a reset of the image atlas makes its triangles again. **/
	var hasImages = false;

	/**
		An image's paint, `PathShader`'s eight texels: its opacity; the map
		from a pixel to where in the image it is, 0 to 1 across; and its
		rect in the image atlas, resampled for the size it covers on screen.
		One that does not fit in the atlas paints nothing.
	**/
	/**
		Tessellates `path`, drawn through `m`, into the mesh, filled by `rule`
		or stroked by `stroke`. A path drawn last frame and again now, turned
		and scaled the same, has its triangles from then moved by the change in
		`m`'s translation instead; one that has gained commands since is
		tessellated again. Returns the contours when `contours` asks
		for them, which a shape whose triangles are reused does not keep.
	**/
	function tessellate(path:ashui.draw.Path, m:Affine, tolerance:Float, aa:Float, rule:FillRule, stroke:Null<ashui.draw.Stroke>,
			contours:Bool):Array<ashui.draw.Flatten.Contour> {
		var known = shapeOf(path);
		if (!contours && known != null && known.data != null && known.a == m.a && known.b == m.b && known.c == m.c && known.d == m.d
			&& known.tolerance == tolerance && known.aa == aa && known.rule == rule && (stroke == null ? known.stroke == null : stroke.same(known.stroke))) {
			var dx = m.e - known.e,
				dy = m.f - known.f,
				data = known.data,
				out = mesh.data;
			var i = 0;
			while (i < data.length) {
				out.push(data[i] + dx);
				out.push(data[i + 1] + dy);
				for (k in 2...Mesh.STRIDE)
					out.push(data[i + k]);
				i += Mesh.STRIDE;
			}
			known.build = builds;
			return NONE;
		}
		var from = mesh.data.length;
		var flat = Flatten.path(path, m, tolerance);
		if (stroke != null)
			Tessellate.stroke(flat, stroke, m.scale(), aa, mesh);
		else
			Tessellate.fill(flat, rule, aa, mesh);
		// Kept the second time a path is drawn: one made afresh each frame is never copied.
		var data = known != null ? mesh.data.slice(from) : null;
		if (known != null) {
			// The same path drawn another way: what was made for it before is replaced.
			var bucket = shapes.get(path.signature());
			bucket.remove(known);
		}
		keep({
			build: builds,
			path: path,
			a: m.a,
			b: m.b,
			c: m.c,
			d: m.d,
			e: m.e,
			f: m.f,
			tolerance: tolerance,
			aa: aa,
			rule: rule,
			stroke: stroke,
			data: data
		});
		return flat;
	}

	static final NONE:Array<ashui.draw.Flatten.Contour> = [];

	/** Whether `brush` is placed by the shape's bounds, which it reads from the contours. **/
	static function needsContours(brush:Brush):Bool
		return brush.gradient != null && brush.gradient.boundingBox;

	/**
		A bitmap fill as an image paint: the map from a pixel to where in the bitmap it is, 0 to 1 across, then the
		bitmap's rect in the atlas, resampled at its size on screen when smoothed and kept at its own size when not, then its smoothing; which axes repeat is in the head.
	**/
	static function encodeBitmapFill(frame:CanvasFrame, fill:ashui.types.Brush.BitmapFill, m:Affine, opacity:Float, out:Array<Float>):Void {
		var bw = fill.bitmap.width, bh = fill.bitmap.height;
		var total = m.after(fill.matrix == null ? Affine.IDENTITY : fill.matrix);
		var back = total.inverse();
		var rect = back == null || bw <= 0 || bh <= 0 ? null : Images.bitmap(fill.bitmap.slot, bw, bh, fill.smooth ? total.scale() * frame.pixelRatio : 1, frame.images);
		if (rect == null) {
			for (_ in 0...PathShader.PAINT_TEXELS)
				for (_ in 0...4)
					out.push(0);
			return;
		}
		var unit = Affine.scaling(1 / bw, 1 / bh).after(back);
		for (v in [
			3.0,
			(fill.repeat : Int),
			opacity,
			0,
			unit.a,
			unit.c,
			unit.e,
			0,
			unit.b,
			unit.d,
			unit.f,
			0,
			rect.x,
			rect.y,
			rect.x + rect.width,
			rect.y + rect.height,
			fill.smooth ? 1.0 : 0.0,
			0,
			0,
			0
		])
			out.push(v);
		for (_ in 0...(PathShader.PAINT_TEXELS - 5) * 4)
			out.push(0);
	}

	/** Writes `tint` and whether the draw is masked into the last three texels of the paint just encoded: its multipliers, its offsets, then the flag. **/
	static function tinted(out:Array<Float>, tint:ColorTransform, masked:Bool):Void {
		var at = out.length - 12;
		out[at + 8] = masked ? 1 : 0;
		out[at + 9] = 0;
		out[at + 10] = 0;
		out[at + 11] = 0;
		out[at] = tint.redMultiplier;
		out[at + 1] = tint.greenMultiplier;
		out[at + 2] = tint.blueMultiplier;
		out[at + 3] = tint.alphaMultiplier;
		out[at + 4] = tint.redOffset;
		out[at + 5] = tint.greenOffset;
		out[at + 6] = tint.blueOffset;
		out[at + 7] = tint.alphaOffset;
	}

	static function encodeImage(frame:CanvasFrame, slot:Int, x:Float, y:Float, w:Float, h:Float, m:Affine, opacity:Float, out:Array<Float>,
			tint:ColorTransform, masked:Bool):Void {
			imagePaint(frame, slot, x, y, w, h, m, opacity, out);
			tinted(out, tint, masked);
	}

	static function imagePaint(frame:CanvasFrame, slot:Int, x:Float, y:Float, w:Float, h:Float, m:Affine, opacity:Float, out:Array<Float>):Void {
		var rect = Images.bitmap(slot, w, h, m.scale() * frame.pixelRatio, frame.images);
		var inverse = m.after(new Affine(w, 0, 0, h, x, y)).inverse();
		if (rect == null || inverse == null) {
			for (_ in 0...PathShader.PAINT_TEXELS)
				for (_ in 0...4)
					out.push(0);
			return;
		}
		for (v in [
			3.0,
			0,
			opacity,
			0,
			inverse.a,
			inverse.c,
			inverse.e,
			0,
			inverse.b,
			inverse.d,
			inverse.f,
			0,
			rect.x,
			rect.y,
			rect.x + rect.width,
			rect.y + rect.height,
			1,
			0,
			0,
			0
		])
			out.push(v);
		for (_ in 0...(PathShader.PAINT_TEXELS - 5) * 4)
			out.push(0);
	}

	/**
		A brush as `PathShader`'s eight texels: a solid colour, or a
		gradient's geometry through `m`, in fractions of the contours'
		bounds for a bounding-box one, and its first four stops. A brush
		that is neither, an image or a blur, paints nothing.
	**/
	static function clipOf(op:DrawOp):Null<DrawClip>
		return switch op {
			case Fill(_, _, _, _, _, clip) | Stroke(_, _, _, _, _, clip) | Image(_, _, _, _, _, _, _, clip): clip;
			case Mesh3D(_) | Pass3D(_) | Blend(_) | Tint(_) | MaskBegin | MaskUse | MaskEnd: null;
		}

	/** Where `clip` starts in the table, from its start, placing it and those outside it the first time. **/
	function place(clip:DrawClip):Int {
		var at = clipAt.get(clip);
		if (at != null)
			return at;
		if (clip.outer != null)
			place(clip.outer);
		at = clipOrder.length * PathShader.CLIP_TEXELS;
		clipAt.set(clip, at);
		clipOrder.push(clip);
		return at;
	}

	/**
		A clip's four texels: its kind (1 box, 2 ellipse, 0 nothing kept),
		the texel the clip outside it starts at, its radius and a pixel's
		size in its own coordinates; the map from a pixel to those, as two
		rows of an affine; and its centre and half its width and height.
	**/
	static function encodeClip(frame:CanvasFrame, clip:DrawClip, next:Int):Array<Float> {
		var m = frame.transform.after(clip.transform);
		var inverse = m.inverse();
		var kind = 0.0, radius = 0.0, cx = 0.0, cy = 0.0, hw = 0.0, hh = 0.0;
		switch clip.shape {
			case Box(x, y, w, h, r):
				kind = 1;
				radius = r;
				cx = x + w / 2;
				cy = y + h / 2;
				hw = Math.max(0, w / 2);
				hh = Math.max(0, h / 2);
			case Ellipse(x, y, rx, ry):
				kind = 2;
				cx = x;
				cy = y;
				hw = Math.max(0.000001, rx);
				hh = Math.max(0.000001, ry);
		}
		if (inverse == null || hw <= 0 || hh <= 0) {
			kind = 0;
			inverse = Affine.IDENTITY;
		}
		return [
			kind,
			next,
			radius,
			m.scale() * frame.pixelRatio,
			inverse.a,
			inverse.c,
			inverse.e,
			0,
			inverse.b,
			inverse.d,
			inverse.f,
			0,
			cx,
			cy,
			hw,
			hh
		];
	}

	static function encode(frame:CanvasFrame, brush:Brush, m:Affine, contours:Array<ashui.draw.Flatten.Contour>, opacity:Float, out:Array<Float>,
			tint:ColorTransform, masked:Bool):Void {
			paint(frame, brush, m, contours, opacity, out);
			tinted(out, tint, masked);
	}

	static function paint(frame:CanvasFrame, brush:Brush, m:Affine, contours:Array<ashui.draw.Flatten.Contour>, opacity:Float, out:Array<Float>):Void {
		inline function rgba(rgb:Int, alpha:Float) {
			out.push((rgb >> 16 & 0xff) / 255);
			out.push((rgb >> 8 & 0xff) / 255);
			out.push((rgb & 0xff) / 255);
			out.push(alpha);
		}
		inline function four(a:Float, b:Float, c:Float, d:Float) {
			out.push(a);
			out.push(b);
			out.push(c);
			out.push(d);
		}
		if (brush.bitmapFill != null) {
			encodeBitmapFill(frame, brush.bitmapFill, m, opacity, out);
			return;
		}
		var p = brush.repeat;
		var inverse = p == null ? null : m.inverse();
		if (p != null && inverse != null) {
			// The map from a pixel to where in the pattern's space it is, then its colour and shape.
			four(4, p.kind, opacity, 0);
			four(inverse.a, inverse.c, inverse.e, 0);
			four(inverse.b, inverse.d, inverse.f, 0);
			rgba(brush.solidRgb, brush.solidAlpha);
			four(p.spacing, p.size, p.coarsen, p.minGap);
			for (_ in 0...PathShader.PAINT_TEXELS - 5)
				four(0, 0, 0, 0);
			return;
		}
		var g = brush.gradient;
		if (g == null || g.stops.length == 0) {
			four(0, 1, opacity, 0);
			four(0, 0, 0, 0);
			four(0, 0, 0, 0);
			if (brush.solidRgb >= 0)
				rgba(brush.solidRgb, brush.solidAlpha);
			else
				four(0, 0, 0, 0);
			for (_ in 0...PathShader.PAINT_TEXELS - 4)
				four(0, 0, 0, 0);
			return;
		}
		var total = m.after(g.matrix == null ? Affine.IDENTITY : g.matrix).inverse();
		if (total == null) {
			// A gradient space the matrix flattens has no colours to give.
			four(0, 1, opacity, 0);
			for (_ in 0...PathShader.PAINT_TEXELS - 1)
				four(0, 0, 0, 0);
			return;
		}
		four(g.radial ? 2 : 1, Math.min(4, g.stops.length), opacity, 0);
		// Geometry in the gradient's own space; a bounding-box one is the shape's bounds in the shape's space.
		if (g.boundingBox) {
			var x0 = Math.POSITIVE_INFINITY,
				y0 = Math.POSITIVE_INFINITY,
				x1 = Math.NEGATIVE_INFINITY,
				y1 = Math.NEGATIVE_INFINITY;
			for (c in contours)
				for (i in 0...c.count()) {
					x0 = Math.min(x0, c.x(i));
					y0 = Math.min(y0, c.y(i));
					x1 = Math.max(x1, c.x(i));
					y1 = Math.max(y1, c.y(i));
				}
			var w = x1 - x0, h = y1 - y0;
			// The contours are already through `m`; the geometry goes back to the shape's space, where the matrix applies.
			var back = m.inverse();
			if (back == null)
				back = Affine.IDENTITY;
			if (g.radial)
				four(back.x(x0 + g.x1 * w, y0 + g.y1 * h), back.y(x0 + g.x1 * w, y0 + g.y1 * h), g.x2 * Math.max(w, h) / m.scale(), 0);
			else
				four(back.x(x0 + g.x1 * w, y0 + g.y1 * h), back.y(x0 + g.x1 * w, y0 + g.y1 * h), back.x(x0 + g.x2 * w, y0 + g.y2 * h),
					back.y(x0 + g.x2 * w, y0 + g.y2 * h));
		} else if (g.radial)
			four(g.x1, g.y1, g.x2, 0);
		else
			four(g.x1, g.y1, g.x2, g.y2);
		// Stops in order; they are usually added so.
		var stops = g.stops;
		var sorted = true;
		for (i in 1...stops.length)
			if (stops[i].offset < stops[i - 1].offset)
				sorted = false;
		if (!sorted) {
			stops = stops.copy();
			stops.sort((a, b) -> a.offset < b.offset ? -1 : a.offset > b.offset ? 1 : 0);
		}
		var n = Std.int(Math.min(4, stops.length));
		four(stops[0].offset, n > 1 ? stops[1].offset : 1, n > 2 ? stops[2].offset : 1, n > 3 ? stops[3].offset : 1);
		for (i in 0...4) {
			var s = stops[i < n ? i : n - 1];
			rgba(s.rgb, s.alpha);
		}
		// The map from a pixel to the gradient's space, its spread and its focus.
		four(total.a, total.c, total.e, g.spread == null ? 0 : g.spread);
		four(total.b, total.d, total.f, g.focal == null ? 0 : g.focal);
		for (_ in 0...PathShader.PAINT_TEXELS - 9)
			four(0, 0, 0, 0);
	}
}

/** A run of a canvas's record: paths, `count` vertices from `first` drawn in `blend`, or meshes. **/
enum CanvasStep {
	Paths(first:Int, count:Int, blend:BlendMode);

	/** A mask's draws, `count` vertices from `first`, drawn into the mask texture. **/
	Mask(first:Int, count:Int);
	Meshes(draws:Array<ScenePainter.SceneDraw>, passes:Array<ashui.draw3d.ScenePass>, scene:ashui.draw3d.Scene3D);
}

/** A path as last drawn: the transform it was drawn through, how, and its triangles once kept. **/
private typedef Shape = {
	build:Int,
	path:ashui.draw.Path,
	a:Float,
	b:Float,
	c:Float,
	d:Float,
	e:Float,
	f:Float,
	tolerance:Float,
	aa:Float,
	rule:FillRule,
	stroke:Null<ashui.draw.Stroke>,
	data:Null<Array<Float>>
}
