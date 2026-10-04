package ashui.core.render;

import ashui.draw.Affine;
import ashui.draw.DrawContext;
import ashui.draw.Flatten;
import ashui.draw.Mesh;
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
	var group:Null<GpuBindGroup> = null;
	var groupPipeline:Null<GpuPipeline> = null;
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
	var bytes:Null<haxe.io.Bytes> = null;

	/** The record's runs, in order: of paths, by their vertices, and of meshes, each drawn by `scenes`. **/
	final steps:Array<CanvasStep> = [];

	var scenes:Null<ScenePainter> = null;

	/** Asks for the canvas to be drawn again; its 3D draws call it as their textures change. **/
	public var repaint:Void->Void = () -> {};

	public function new() {}

	/** Frees what its 3D draws uploaded. **/
	public function dispose():Void
		if (scenes != null) {
			scenes.dispose();
			scenes = null;
		}

	public function play(frame:CanvasFrame, ctx:DrawContext):Void {
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
			if (step.match(Meshes(_)) && scenes == null)
				scenes = new ScenePainter(() -> repaint());
		if (scenes != null)
			scenes.beginFrame();
		var run = 0;
		for (step in steps)
			switch step {
				case Paths(first, count):
					drawPaths(frame, first, count);
				case Meshes(draws, scene):
					scenes.draw(frame, run++, draws, scene);
			}
		if (scenes != null)
			scenes.endFrame();
	}

	function drawPaths(frame:CanvasFrame, first:Int, count:Int):Void {
		var atlas = frame.images;
		var pipeline = frame.bind(PathShader.WGSL);
		if (group == null || groupPipeline != pipeline.pipeline || groupAtlas != atlas.revision) {
			if (group != null)
				group.destroy();
			// The image atlas and its sampler, then the canvas's data, which is fetched, never sampled.
			var bindings = new GpuBindings();
			bindings.texture(atlas.view);
			bindings.sampler(frame.imageSampler);
			bindings.texture(view);
			group = frame.device.bindGroup(pipeline.pipeline, PathShader.TEXTURE_canvas_GROUP, bindings);
			bindings.destroy();
			groupPipeline = pipeline.pipeline;
			groupAtlas = atlas.revision;
		}
		frame.encoder.renderSetBindGroup(PathShader.TEXTURE_canvas_GROUP, group);
		frame.encoder.renderDrawRange(count, 1, first, frame.record);
	}

	function build(frame:CanvasFrame, ctx:DrawContext):Void {
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
		function endPaths() {
			if (mesh.vertexCount() > pathsFrom)
				steps.push(Paths(pathsFrom, mesh.vertexCount() - pathsFrom));
			pathsFrom = mesh.vertexCount();
		}
		for (op in ctx.ops) {
			var before = mesh.vertexCount();
			switch op {
				case Mesh3D(m, transform, scene, opacity):
					endPaths();
					// Meshes drawn one after another, seen the same way, are one run, sharing depth.
					var last = steps.length > 0 ? steps[steps.length - 1] : null;
					switch last {
						case Meshes(draws, s) if (last != null && s == scene):
							draws.push({mesh: m, transform: transform, opacity: opacity});
						case _:
							steps.push(Meshes([{mesh: m, transform: transform, opacity: opacity}], scene));
					}
					continue;
				case Fill(path, brush, rule, transform, opacity, clip):
					var m = frame.transform.after(transform);
					var contours = Flatten.path(path, m, tolerance);
					Tessellate.fill(contours, rule, aa, mesh);
					if (mesh.vertexCount() > before)
						encode(brush, m, contours, opacity, paints);
				case Stroke(path, stroke, brush, transform, opacity, clip):
					var m = frame.transform.after(transform);
					var contours = Flatten.path(path, m, tolerance);
					Tessellate.stroke(contours, stroke, m.scale(), aa, mesh);
					if (mesh.vertexCount() > before)
						encode(brush, m, contours, opacity, paints);
				case Image(slot, x, y, w, h, transform, opacity, clip):
					hasImages = true;
					var m = frame.transform.after(transform);
					var contours = Flatten.path(new ashui.draw.Path().rect(x, y, w, h), m, tolerance);
					Tessellate.fill(contours, NonZero, aa, mesh);
					if (mesh.vertexCount() > before)
						encodeImage(frame, slot, x, y, w, h, m, opacity, paints);
			}
			if (mesh.vertexCount() > before) {
				starts.push(before);
				drawClips.push(clipOf(op));
			}
		}
		endPaths();
		vertexCount = mesh.vertexCount();
		if (vertexCount == 0)
			return;
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
			var k = starts[i] * Mesh.STRIDE, end = (i + 1 < draws ? starts[i + 1] : vertexCount) * Mesh.STRIDE;
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
			rows = needed + (needed >> 1);
			var extent = new GpuExtent3D(PathShader.ROW_TEXELS);
			extent.height(rows);
			texture = frame.device.texture(new GpuTextureDescriptor(extent, TextureFormat.Rgba32float, GpuFlags.TEXTURE_BINDING | GpuFlags.TEXTURE_COPY_DST));
			view = texture.createView(new GpuTextureViewDescriptor());
			if (group != null)
				group.destroy();
			group = null;
		}
		frame.device.queue().writeTexture(texture, bytes, PathShader.ROW_TEXELS, needed, PathShader.ROW_TEXELS * 16);
	}

	/** Whether the record draws an image, so a reset of the image atlas makes its triangles again. **/
	var hasImages = false;

	/**
		An image's paint, `PathShader`'s eight texels: its opacity; the map
		from a pixel to where in the image it is, 0 to 1 across; and its
		rect in the image atlas, resampled for the size it covers on screen.
		One that does not fit in the atlas paints nothing.
	**/
	static function encodeImage(frame:CanvasFrame, slot:Int, x:Float, y:Float, w:Float, h:Float, m:Affine, opacity:Float, out:Array<Float>):Void {
		var rect = Images.bitmap(slot, w, h, m.scale() * frame.pixelRatio, frame.images);
		var inverse = m.after(new Affine(w, 0, 0, h, x, y)).inverse();
		if (rect == null || inverse == null) {
			for (_ in 0...8)
				for (_ in 0...4)
					out.push(0);
			return;
		}
		for (v in [3.0, 0, opacity, 0, inverse.a, inverse.c, inverse.e, 0, inverse.b, inverse.d, inverse.f, 0, rect.x, rect.y, rect.x + rect.width,
			rect.y + rect.height])
			out.push(v);
		for (_ in 0...16)
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
			case Mesh3D(_): null;
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
		return [kind, next, radius, m.scale() * frame.pixelRatio, inverse.a, inverse.c, inverse.e, 0, inverse.b, inverse.d, inverse.f, 0, cx, cy, hw, hh];
	}

	static function encode(brush:Brush, m:Affine, contours:Array<ashui.draw.Flatten.Contour>, opacity:Float, out:Array<Float>):Void {
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
		var g = brush.gradient;
		if (g == null || g.stops.length == 0) {
			four(0, 1, opacity, 0);
			four(0, 0, 0, 0);
			four(0, 0, 0, 0);
			if (brush.solidRgb >= 0)
				rgba(brush.solidRgb, brush.solidAlpha);
			else
				four(0, 0, 0, 0);
			for (_ in 0...4)
				four(0, 0, 0, 0);
			return;
		}
		four(g.radial ? 2 : 1, Math.min(4, g.stops.length), opacity, 0);
		if (g.boundingBox) {
			var x0 = Math.POSITIVE_INFINITY, y0 = Math.POSITIVE_INFINITY, x1 = Math.NEGATIVE_INFINITY, y1 = Math.NEGATIVE_INFINITY;
			for (c in contours)
				for (i in 0...c.count()) {
					x0 = Math.min(x0, c.x(i));
					y0 = Math.min(y0, c.y(i));
					x1 = Math.max(x1, c.x(i));
					y1 = Math.max(y1, c.y(i));
				}
			var w = x1 - x0, h = y1 - y0;
			if (g.radial)
				four(x0 + g.x1 * w, y0 + g.y1 * h, g.x2 * Math.max(w, h), 0);
			else
				four(x0 + g.x1 * w, y0 + g.y1 * h, x0 + g.x2 * w, y0 + g.y2 * h);
		} else if (g.radial)
			four(m.x(g.x1, g.y1), m.y(g.x1, g.y1), g.x2 * m.scale(), 0);
		else
			four(m.x(g.x1, g.y1), m.y(g.x1, g.y1), m.x(g.x2, g.y2), m.y(g.x2, g.y2));
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
		four(0, 0, 0, 0);
	}
}

/** A run of a canvas's record: paths, `count` vertices from `first`, or meshes. **/
enum CanvasStep {
	Paths(first:Int, count:Int);
	Meshes(draws:Array<ScenePainter.SceneDraw>, scene:ashui.draw3d.Scene3D);
}
