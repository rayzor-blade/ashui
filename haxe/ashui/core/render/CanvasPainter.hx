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

	/** What the triangles were made for. **/
	var madeFor:Null<DrawContext> = null;

	var madeKey = "";

	public function new() {}

	public function play(frame:CanvasFrame, ctx:DrawContext):Void {
		var t = frame.transform;
		var key = '${t.a} ${t.b} ${t.c} ${t.d} ${t.e} ${t.f} ${frame.pixelRatio}';
		if (ctx != madeFor || key != madeKey) {
			build(frame, ctx);
			madeFor = ctx;
			madeKey = key;
		}
		if (vertexCount == 0)
			return;
		var pipeline = frame.bind(PathShader.WGSL);
		if (group == null || groupPipeline != pipeline.pipeline) {
			if (group != null)
				group.destroy();
			// The texture alone: it is fetched, never sampled, as the records are.
			var bindings = new GpuBindings();
			bindings.texture(view);
			group = frame.device.bindGroup(pipeline.pipeline, PathShader.TEXTURE_canvas_GROUP, bindings);
			bindings.destroy();
			groupPipeline = pipeline.pipeline;
		}
		frame.encoder.renderSetBindGroup(PathShader.TEXTURE_canvas_GROUP, group);
		frame.encoder.renderDrawRange(vertexCount, 1, 0, frame.record);
	}

	function build(frame:CanvasFrame, ctx:DrawContext):Void {
		// A target pixel, in the layout units the triangles are in.
		var aa = 1 / frame.pixelRatio;
		var tolerance = TOLERANCE / frame.pixelRatio;
		var meshes:Array<Mesh> = [];
		var paints:Array<Array<Float>> = [];
		for (op in ctx.ops) {
			var mesh = new Mesh();
			var paint:Array<Float>;
			switch op {
				case Fill(path, brush, rule, transform, opacity):
					var m = frame.transform.after(transform);
					var contours = Flatten.path(path, m, tolerance);
					Tessellate.fill(contours, rule, aa, mesh);
					paint = encode(brush, m, contours, opacity);
				case Stroke(path, stroke, brush, transform, opacity):
					var m = frame.transform.after(transform);
					var contours = Flatten.path(path, m, tolerance);
					Tessellate.stroke(contours, stroke, m.scale(), aa, mesh);
					paint = encode(brush, m, contours, opacity);
			}
			if (mesh.vertexCount() > 0) {
				meshes.push(mesh);
				paints.push(paint);
			}
		}
		vertexCount = 0;
		for (m in meshes)
			vertexCount += m.vertexCount();
		if (vertexCount == 0)
			return;
		var texels = vertexCount * PathShader.VERTEX_TEXELS + paints.length * PathShader.PAINT_TEXELS;
		var needed = Std.int(Math.ceil(texels / PathShader.ROW_TEXELS));
		var bytes = haxe.io.Bytes.alloc(needed * PathShader.ROW_TEXELS * 16);
		var at = 0;
		inline function put(v:Float) {
			bytes.setFloat(at, v);
			at += 4;
		}
		for (i => mesh in meshes) {
			var paintTexel = vertexCount * PathShader.VERTEX_TEXELS + i * PathShader.PAINT_TEXELS;
			var d = mesh.data, k = 0;
			while (k < d.length) {
				put(d[k]);
				put(d[k + 1]);
				put(d[k + 2]);
				put(paintTexel);
				for (j in 3...Mesh.STRIDE)
					put(d[k + j]);
				k += Mesh.STRIDE;
			}
		}
		for (p in paints)
			for (v in p)
				put(v);
		if (texture == null || needed > rows) {
			if (texture != null)
				texture.destroy();
			rows = needed + (needed >> 1);
			var size = new GpuExtent3D(PathShader.ROW_TEXELS);
			size.height(rows);
			texture = frame.device.texture(new GpuTextureDescriptor(size, TextureFormat.Rgba32float, GpuFlags.TEXTURE_BINDING | GpuFlags.TEXTURE_COPY_DST));
			view = texture.createView(new GpuTextureViewDescriptor());
			if (group != null)
				group.destroy();
			group = null;
		}
		frame.device.queue().writeTexture(texture, bytes, PathShader.ROW_TEXELS, needed, PathShader.ROW_TEXELS * 16);
	}

	/**
		A brush as `PathShader`'s eight texels: a solid colour, or a
		gradient's geometry through `m`, in fractions of the contours'
		bounds for a bounding-box one, and its first four stops. A brush
		that is neither, an image or a blur, paints nothing.
	**/
	static function encode(brush:Brush, m:Affine, contours:Array<ashui.draw.Flatten.Contour>, opacity:Float):Array<Float> {
		inline function rgba(rgb:Int, alpha:Float):Array<Float>
			return [(rgb >> 16 & 0xff) / 255, (rgb >> 8 & 0xff) / 255, (rgb & 0xff) / 255, alpha];
		var g = brush.gradient;
		if (g == null || g.stops.length == 0) {
			var color = brush.solidRgb >= 0 ? rgba(brush.solidRgb, brush.solidAlpha) : [0.0, 0, 0, 0];
			return [0.0, 1, opacity, 0, 0, 0, 0, 0, 0, 0, 0, 0].concat(color).concat([for (_ in 0...16) 0.0]);
		}
		var geo:Array<Float>;
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
			geo = g.radial ? [x0 + g.x1 * w, y0 + g.y1 * h, g.x2 * Math.max(w, h), 0] : [x0 + g.x1 * w, y0 + g.y1 * h, x0 + g.x2 * w, y0 + g.y2 * h];
		} else
			geo = g.radial ? [m.x(g.x1, g.y1), m.y(g.x1, g.y1), g.x2 * m.scale(), 0] : [m.x(g.x1, g.y1), m.y(g.x1, g.y1), m.x(g.x2, g.y2), m.y(g.x2, g.y2)];
		var stops = g.stops.copy();
		stops.sort((a, b) -> a.offset < b.offset ? -1 : a.offset > b.offset ? 1 : 0);
		var n = Std.int(Math.min(4, stops.length));
		var offsets = [for (i in 0...4) i < n ? stops[i].offset : 1.0];
		var out = [g.radial ? 2.0 : 1.0, n, opacity, 0].concat(geo).concat(offsets);
		for (i in 0...4)
			out = out.concat(i < n ? rgba(stops[i].rgb, stops[i].alpha) : rgba(stops[n - 1].rgb, stops[n - 1].alpha));
		return out.concat([0.0, 0, 0, 0]);
	}
}
