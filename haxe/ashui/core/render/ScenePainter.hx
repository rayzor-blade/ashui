package ashui.core.render;

import ashui.draw3d.Light;
import ashui.draw3d.Material;
import ashui.draw3d.MeshData;
import ashui.draw3d.Scene3D;
import ashui.math.Mat4;
import ashui.math.Vec3;
import ashui.types.Bitmap;
import gpu.GpuBindGroup;
import gpu.GpuBindings;
import gpu.GpuBuffer;
import gpu.GpuBufferDescriptor;
import gpu.GpuColor;
import gpu.GpuExtent3D;
import gpu.GpuPipeline;
import gpu.GpuRenderPassColorAttachment;
import gpu.GpuRenderPassDepthStencilAttachment;
import gpu.GpuRenderPassDescriptor;
import gpu.GpuSampler;
import gpu.GpuSamplerDescriptor;
import gpu.GpuTexelCopyBufferLayout;
import gpu.GpuTexelCopyTextureInfo;
import gpu.GpuTexture;
import gpu.GpuTextureDescriptor;
import gpu.GpuTextureView;
import gpu.GpuTextureViewDescriptor;
import gpu.TextureFormat;

/** A mesh drawn in a run of 3D draws. **/
typedef SceneDraw = {mesh:MeshData, transform:Mat4, opacity:Float};

/** A texture on the GPU and its view. **/
private typedef Uploaded = {texture:GpuTexture, view:GpuTextureView};

/** Where one run of a canvas's 3D draws is rendered, and what it was rendered for. **/
private class SceneLayer {
	public var color:Null<GpuTexture> = null;
	public var colorView:Null<GpuTextureView> = null;
	public var depth:Null<GpuTexture> = null;
	public var depthView:Null<GpuTextureView> = null;
	public var group:Null<GpuBindGroup> = null;
	public var groupPipeline:Null<GpuPipeline> = null;
	public var width = 0;
	public var height = 0;
	public var madeFor:Null<Array<SceneDraw>> = null;

	public function new() {}

	public function destroy():Void {
		if (group != null)
			group.destroy();
		if (colorView != null)
			colorView.destroy();
		if (color != null)
			color.destroy();
		if (depthView != null)
			depthView.destroy();
		if (depth != null)
			depth.destroy();
		group = null;
		color = null;
		depth = null;
	}
}

/**
	Plays a canvas's runs of 3D draws: each run rendered into a layer of
	its own, a colour and a depth texture `SUPERSAMPLE` times the size of
	the canvas's box on screen, then drawn over the box by `SceneShader`,
	filtered down. A layer is rendered again only when its draws or its
	size change; otherwise it is only drawn again.

	A mesh's vertices and indices, and its material's textures with all
	their mip levels, are uploaded the first time it is drawn and kept
	while it is drawn; those not drawn in a frame are freed.
**/
class ScenePainter {
	/** Layer pixels to a target pixel, each way: the antialiasing. **/
	public static inline var SUPERSAMPLE = 2;

	/** The largest layer, each way, in pixels. **/
	static inline var MAX_LAYER = 4096;

	static inline var DEPTH_FORMAT = TextureFormat.Depth24plus;

	final layers:Array<SceneLayer> = [];
	final meshes = new haxe.ds.ObjectMap<MeshData, {vertices:GpuBuffer, indices:GpuBuffer, used:Int}>();
	final materials = new haxe.ds.ObjectMap<Material, {group:GpuBindGroup, used:Int, buffers:Int}>();
	final textures = new Map<String, Uploaded & {used:Int}>();
	final pipelines = new Map<Int, GpuPipeline>();
	var defaults:Null<{white:Uploaded, flat:Uploaded}> = null;
	var sampler:Null<GpuSampler> = null;
	var layerSampler:Null<GpuSampler> = null;
	var sceneBuffer:Null<GpuBuffer> = null;
	var drawBuffer:Null<GpuBuffer> = null;
	var drawCapacity = 0;

	/** Counts the buffers made; a material group made for older ones is made again. **/
	var buffers = 0;

	var frameCount = 0;

	public function new() {}

	/** Called once a canvas frame, before its runs: what was drawn last frame and not since is freed. **/
	public function beginFrame():Void
		frameCount++;

	/** After the canvas's runs: frees meshes, materials and textures no run drew this frame. **/
	public function endFrame():Void {
		for (m => g in meshes)
			if (g.used != frameCount) {
				g.vertices.destroy();
				g.indices.destroy();
				meshes.remove(m);
			}
		for (m => g in materials)
			if (g.used != frameCount) {
				g.group.destroy();
				materials.remove(m);
			}
		for (k => t in textures)
			if (t.used != frameCount) {
				t.view.destroy();
				t.texture.destroy();
				textures.remove(k);
			}
	}

	/** Draws run `index` of the canvas's 3D runs, `draws` seen as `scene` says, over the canvas's box. **/
	public function draw(frame:CanvasFrame, index:Int, draws:Array<SceneDraw>, scene:Scene3D):Void {
		while (layers.length <= index)
			layers.push(new SceneLayer());
		var layer = layers[index];
		var w = Std.int(Math.min(MAX_LAYER, Math.max(1, Math.ceil(frame.width * frame.scale * SUPERSAMPLE))));
		var h = Std.int(Math.min(MAX_LAYER, Math.max(1, Math.ceil(frame.height * frame.scale * SUPERSAMPLE))));
		var resized = w != layer.width || h != layer.height || layer.color == null;
		if (resized) {
			layer.destroy();
			makeLayer(frame, layer, w, h);
		}
		// Resources are marked used whether or not the layer is rendered again, so they outlive a frame that only composites.
		for (d in draws)
			markUsed(frame, d.mesh);
		if (resized || layer.madeFor != draws) {
			render(frame, layer, draws, scene);
			layer.madeFor = draws;
		}
		composite(frame, layer);
	}

	/** Frees every layer and upload. **/
	public function dispose():Void {
		for (l in layers)
			l.destroy();
		layers.resize(0);
		frameCount++;
		endFrame();
		if (sceneBuffer != null)
			sceneBuffer.destroy();
		if (drawBuffer != null)
			drawBuffer.destroy();
		sceneBuffer = drawBuffer = null;
	}

	function makeLayer(frame:CanvasFrame, layer:SceneLayer, w:Int, h:Int):Void {
		var size = new GpuExtent3D(w);
		size.height(h);
		layer.color = frame.device.texture(new GpuTextureDescriptor(size, frame.format, GpuFlags.TEXTURE_RENDER_ATTACHMENT | GpuFlags.TEXTURE_BINDING));
		layer.colorView = layer.color.createView(new GpuTextureViewDescriptor());
		layer.depth = frame.device.texture(new GpuTextureDescriptor(size, DEPTH_FORMAT, GpuFlags.TEXTURE_RENDER_ATTACHMENT));
		layer.depthView = layer.depth.createView(new GpuTextureViewDescriptor());
		layer.width = w;
		layer.height = h;
		layer.madeFor = null;
		layer.group = null;
	}

	function markUsed(frame:CanvasFrame, mesh:MeshData):Void {
		upload(frame, mesh).used = frameCount;
		var m = mesh.material;
		var group = materials.get(m);
		if (group != null)
			group.used = frameCount;
		for (t in [m.baseColorTexture, m.emissiveTexture])
			if (t != null)
				texture(frame, t, true).used = frameCount;
		for (t in [m.normalTexture, m.metallicRoughnessTexture, m.occlusionTexture])
			if (t != null)
				texture(frame, t, false).used = frameCount;
	}

	function render(frame:CanvasFrame, layer:SceneLayer, draws:Array<SceneDraw>, scene:Scene3D):Void {
		var device = frame.device;
		ensureBuffers(frame, draws.length);
		var aspect = frame.width / Math.max(frame.height, 0.0001);
		var viewProjection = scene.camera.projection(aspect).mul(scene.camera.view());
		device.queue().writeBuffer(sceneBuffer, 0, sceneBytes(scene, viewProjection), ashui.shaders.Scene.ROWS * 16);
		// Opaque first, in order; then blended, furthest first, so each blends over what is behind it.
		var order = [for (i in 0...draws.length) i];
		var eye = scene.camera.eye;
		inline function blended(i:Int)
			return draws[i].mesh.material.alphaMode == Blend || draws[i].opacity < 1;
		inline function distance(i:Int)
			return draws[i].transform.transformPoint(draws[i].mesh.min.lerp(draws[i].mesh.max, 0.5)).distance(eye);
		order.sort((a, b) -> {
			var ba = blended(a), bb = blended(b);
			if (ba != bb)
				return ba ? 1 : -1;
			if (!ba)
				return a - b;
			var da = distance(a), db = distance(b);
			return da > db ? -1 : da < db ? 1 : 0;
		});
		var bytes = haxe.io.Bytes.alloc(draws.length * ashui.shaders.MeshDraw.ROWS * 16);
		for (slot in 0...order.length)
			writeDraw(bytes, slot * ashui.shaders.MeshDraw.ROWS * 16, draws[order[slot]]);
		device.queue().writeBuffer(drawBuffer, 0, bytes, bytes.length);
		var groups = [for (i in order) materialGroup(frame, draws[i].mesh.material)];
		var bg = scene.background, ba = scene.backgroundAlpha;
		frame.suspend(encoder -> {
			var color = new GpuRenderPassColorAttachment(Clear, Store);
			color.viewTextureView(layer.colorView);
			// Premultiplied, as the layer is composited.
			color.clearValue(new GpuColor((bg >> 16 & 0xff) / 255 * ba, (bg >> 8 & 0xff) / 255 * ba, (bg & 0xff) / 255 * ba, ba));
			var depth = new GpuRenderPassDepthStencilAttachment();
			depth.viewTextureView(layer.depthView);
			depth.depthClearValue(1);
			depth.depthLoadOp(Clear);
			depth.depthStoreOp(Discard);
			var pass = new GpuRenderPassDescriptor();
			pass.addColorAttachments(color);
			pass.depthStencilAttachment(depth);
			encoder.beginRenderPass(pass);
			for (slot in 0...order.length) {
				var d = draws[order[slot]];
				var gpu = meshes.get(d.mesh);
				encoder.renderSetPipeline(pipeline(frame, d.mesh.material, d.opacity));
				encoder.renderSetBindGroup(0, groups[slot]);
				encoder.renderSetVertexBuffer(0, gpu.vertices);
				encoder.renderSetIndexBufferRange(gpu.indices, Uint32, 0, d.mesh.indexCount * 4);
				encoder.renderDrawIndexedRange(d.mesh.indexCount, 1, 0, 0, slot);
			}
			encoder.renderEnd();
		});
	}

	function composite(frame:CanvasFrame, layer:SceneLayer):Void {
		var pass = frame.bind(SceneShader.WGSL);
		if (layer.group == null || layer.groupPipeline != pass.pipeline) {
			if (layer.group != null)
				layer.group.destroy();
			if (layerSampler == null) {
				var d = new GpuSamplerDescriptor();
				d.magFilter(Linear);
				d.minFilter(Linear);
				layerSampler = frame.device.sampler(d);
			}
			var bindings = new GpuBindings();
			bindings.texture(layer.colorView);
			bindings.sampler(layerSampler);
			layer.group = frame.device.bindGroup(pass.pipeline, SceneShader.TEXTURE_canvasLayer_GROUP, bindings);
			bindings.destroy();
			layer.groupPipeline = pass.pipeline;
		}
		frame.encoder.renderSetBindGroup(SceneShader.TEXTURE_canvasLayer_GROUP, layer.group);
		frame.encoder.renderDrawRange(6, 1, 0, frame.record);
	}

	/** The pipeline for a material: culled unless double-sided, writing depth unless blended. **/
	function pipeline(frame:CanvasFrame, material:Material, opacity:Float):GpuPipeline {
		var blended = material.alphaMode == Blend || opacity < 1;
		var key = (material.doubleSided ? 1 : 0) | (blended ? 2 : 0);
		var made = pipelines.get(key);
		if (made != null)
			return made;
		var device = frame.device;
		var shader = device.createShader(MeshShader.WGSL);
		var builder = device.pipeline();
		builder.shader(shader, "vertex", "fragment");
		builder.vertexBuffer(MeshData.STRIDE, Vertex);
		builder.attribute(Float32x3, MeshData.POSITION_OFFSET, MeshShader.INPUT_position);
		builder.attribute(Float32x3, MeshData.NORMAL_OFFSET, MeshShader.INPUT_normal);
		builder.attribute(Float32x2, MeshData.UV_OFFSET, MeshShader.INPUT_uv);
		builder.attribute(Float32x4, MeshData.TANGENT_OFFSET, MeshShader.INPUT_tangent);
		builder.target(frame.format, GpuFlags.COLOR_WRITE_ALL);
		// Premultiplied into the layer, as it is composited.
		builder.blend(SrcAlpha, OneMinusSrcAlpha, Add, One, OneMinusSrcAlpha, Add);
		builder.depth(DEPTH_FORMAT, !blended, Less);
		builder.primitive(TriangleList, material.doubleSided ? None : Back, Ccw);
		made = builder.build();
		pipelines.set(key, made);
		return made;
	}

	/** Its textures, the scene and the draws: a material's bind group, made for its pipeline. **/
	function materialGroup(frame:CanvasFrame, material:Material):GpuBindGroup {
		var known = materials.get(material);
		if (known != null && known.buffers == buffers) {
			known.used = frameCount;
			return known.group;
		}
		if (known != null)
			known.group.destroy();
		var d = ensureDefaults(frame);
		inline function tex(b:Null<Bitmap>, srgb:Bool, fallback:Uploaded):GpuTextureView
			return b != null ? texture(frame, b, srgb).view : fallback.view;
		var bindings = new GpuBindings();
		for (view in [
			tex(material.baseColorTexture, true, d.white),
			tex(material.normalTexture, false, d.flat),
			tex(material.metallicRoughnessTexture, false, d.white),
			tex(material.emissiveTexture, true, d.white),
			tex(material.occlusionTexture, false, d.white)
		]) {
			bindings.texture(view);
			bindings.sampler(sampler);
		}
		bindings.buffer(sceneBuffer);
		bindings.buffer(drawBuffer);
		var group = frame.device.bindGroup(pipeline(frame, material, 1), 0, bindings);
		bindings.destroy();
		materials.set(material, {group: group, used: frameCount, buffers: buffers});
		return group;
	}

	function ensureBuffers(frame:CanvasFrame, draws:Int):Void {
		if (sceneBuffer == null)
			sceneBuffer = frame.device.createBuffer(new GpuBufferDescriptor(ashui.shaders.Scene.ROWS * 16, GpuFlags.BUFFER_STORAGE | GpuFlags.BUFFER_COPY_DST));
		if (drawBuffer == null || draws > drawCapacity) {
			if (drawBuffer != null)
				drawBuffer.destroy();
			drawCapacity = Std.int(Math.max(16, draws + (draws >> 1)));
			drawBuffer = frame.device.createBuffer(new GpuBufferDescriptor(drawCapacity * ashui.shaders.MeshDraw.ROWS * 16,
				GpuFlags.BUFFER_STORAGE | GpuFlags.BUFFER_COPY_DST));
			buffers++;
		}
	}

	function ensureDefaults(frame:CanvasFrame):{white:Uploaded, flat:Uploaded} {
		if (defaults != null)
			return defaults;
		var s = new GpuSamplerDescriptor();
		s.addressModeU(Repeat);
		s.addressModeV(Repeat);
		s.magFilter(Linear);
		s.minFilter(Linear);
		s.mipmapFilter(Linear);
		s.maxAnisotropy(8);
		sampler = frame.device.sampler(s);
		function solid(r:Int, g:Int, b:Int):Uploaded {
			var px = haxe.io.Bytes.alloc(4);
			px.set(0, r);
			px.set(1, g);
			px.set(2, b);
			px.set(3, 255);
			var size = new GpuExtent3D(1);
			size.height(1);
			var t = frame.device.texture(new GpuTextureDescriptor(size, TextureFormat.Rgba8unorm, GpuFlags.TEXTURE_BINDING | GpuFlags.TEXTURE_COPY_DST));
			frame.device.queue().writeTexture(t, px, 1, 1, 4);
			return {texture: t, view: t.createView(new GpuTextureViewDescriptor())};
		}
		return defaults = {white: solid(255, 255, 255), flat: solid(128, 128, 255)};
	}

	function upload(frame:CanvasFrame, mesh:MeshData):{vertices:GpuBuffer, indices:GpuBuffer, used:Int} {
		var known = meshes.get(mesh);
		if (known != null)
			return known;
		var device = frame.device;
		// Sizes rounded up to four bytes, as buffer writes need.
		var vb = device.createBuffer(new GpuBufferDescriptor(Std.int(Math.max(16, mesh.vertices.length)), GpuFlags.BUFFER_VERTEX | GpuFlags.BUFFER_COPY_DST));
		var ib = device.createBuffer(new GpuBufferDescriptor(Std.int(Math.max(16, mesh.indices.length)), GpuFlags.BUFFER_INDEX | GpuFlags.BUFFER_COPY_DST));
		if (mesh.vertices.length > 0)
			device.queue().writeBuffer(vb, 0, mesh.vertices, mesh.vertices.length);
		if (mesh.indices.length > 0)
			device.queue().writeBuffer(ib, 0, mesh.indices, mesh.indices.length);
		var made = {vertices: vb, indices: ib, used: frameCount};
		meshes.set(mesh, made);
		return made;
	}

	/**
		`bitmap` on the GPU with every mip level, each resampled from the
		whole image; `srgb` for colour, which the GPU turns linear as it is
		sampled.
	**/
	function texture(frame:CanvasFrame, bitmap:Bitmap, srgb:Bool):Uploaded & {used:Int} {
		var key = '${bitmap.slot}/${srgb ? 1 : 0}';
		var known = textures.get(key);
		if (known != null)
			return known;
		var w = bitmap.width, h = bitmap.height;
		var levels = 1;
		while ((w >> levels) > 0 || (h >> levels) > 0)
			levels++;
		var size = new GpuExtent3D(w);
		size.height(h);
		var descriptor = new GpuTextureDescriptor(size, srgb ? TextureFormat.Rgba8unormSrgb : TextureFormat.Rgba8unorm,
			GpuFlags.TEXTURE_BINDING | GpuFlags.TEXTURE_COPY_DST);
		descriptor.mipLevelCount(levels);
		var t = frame.device.texture(descriptor);
		for (level in 0...levels) {
			var lw = Std.int(Math.max(1, w >> level)), lh = Std.int(Math.max(1, h >> level));
			var px = haxe.io.Bytes.alloc(lw * lh * 4);
			@:privateAccess ashui.core.externs.BitmapNative.blinc_bitmap_resample(bitmap.slot, lw, lh, (Fill : ashui.types.Brush.ImageFit), px);
			var destination = new GpuTexelCopyTextureInfo(t);
			destination.mipLevel(level);
			var layout = new GpuTexelCopyBufferLayout();
			layout.bytesPerRow(lw * 4);
			layout.rowsPerImage(lh);
			var extent = new GpuExtent3D(lw);
			extent.height(lh);
			frame.device.queue().writeTextureWith(destination, px, layout, extent);
		}
		var made = {texture: t, view: t.createView(new GpuTextureViewDescriptor()), used: frameCount};
		textures.set(key, made);
		return made;
	}

	static function linear(c:Int):Float {
		var v = c / 255;
		return v <= 0.04045 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4);
	}

	static function sceneBytes(scene:Scene3D, viewProjection:Mat4):haxe.io.Bytes {
		var out = haxe.io.Bytes.alloc(ashui.shaders.Scene.ROWS * 16);
		viewProjection.write(out, 0);
		var lights = scene.lights.slice(0, ashui.shaders.Scene.MAX_LIGHTS);
		var eye = scene.camera.eye;
		row(out, 4, eye.x, eye.y, eye.z, lights.length);
		var a = scene.ambient, s = scene.ambientStrength;
		row(out, 5, linear(a >> 16 & 0xff) * s, linear(a >> 8 & 0xff) * s, linear(a & 0xff) * s, scene.exposure);
		for (i in 0...lights.length) {
			var at = ashui.shaders.Scene.FIRST_LIGHT + i * ashui.shaders.Scene.LIGHT_ROWS;
			inline function rgb(c:Int, k:Float)
				row(out, at + 1, linear(c >> 16 & 0xff) * k, linear(c >> 8 & 0xff) * k, linear(c & 0xff) * k, 0);
			switch lights[i] {
				case Directional(direction, color, intensity):
					row(out, at, 0, 0, 0, 0);
					rgb(color, intensity);
					row(out, at + 3, direction.x, direction.y, direction.z, 0);
				case Point(position, color, intensity, range):
					row(out, at, 1, range, 0, 0);
					rgb(color, intensity);
					row(out, at + 2, position.x, position.y, position.z, 0);
					row(out, at + 3, 0, -1, 0, 0);
				case Spot(position, direction, color, intensity, range, inner, outer):
					row(out, at, 2, range, Math.cos(inner), Math.cos(outer));
					rgb(color, intensity);
					row(out, at + 2, position.x, position.y, position.z, 0);
					row(out, at + 3, direction.x, direction.y, direction.z, 0);
			}
		}
		return out;
	}

	static function writeDraw(out:haxe.io.Bytes, offset:Int, d:SceneDraw):Void {
		d.transform.write(out, offset);
		var n = d.transform.normalMatrix().m;
		for (c in 0...3)
			for (r in 0...4)
				out.setFloat(offset + (4 + c) * 16 + r * 4, r < 3 ? n[c * 4 + r] : 0);
		var m = d.mesh.material;
		var at = Std.int(offset / 16);
		row(out, at + 7, linear(m.baseColor >> 16 & 0xff), linear(m.baseColor >> 8 & 0xff), linear(m.baseColor & 0xff), m.alpha);
		row(out, at + 8, m.metallic, m.roughness, m.normalScale, m.occlusionTexture != null ? m.occlusionStrength : 0);
		var e = m.emissive, k = m.emissiveStrength;
		row(out, at + 9, linear(e >> 16 & 0xff) * k, linear(e >> 8 & 0xff) * k, linear(e & 0xff) * k, m.alphaCutoff);
		row(out, at + 10, m.normalTexture != null ? 1 : 0, m.unlit ? 1 : 0, (m.alphaMode : Int), d.opacity);
		row(out, at + 11, 0, 0, 0, 0);
	}

	static inline function row(out:haxe.io.Bytes, at:Int, x:Float, y:Float, z:Float, w:Float):Void {
		out.setFloat(at * 16, x);
		out.setFloat(at * 16 + 4, y);
		out.setFloat(at * 16 + 8, z);
		out.setFloat(at * 16 + 12, w);
	}
}
