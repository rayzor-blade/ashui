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

	/** `MeshTextures.revision` when it was rendered. **/
	public var textures = -1;

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

	A mesh's vertices and indices are uploaded the first time it is drawn
	and kept while it is drawn; those not drawn in a frame are freed. A
	texture, with all its mip levels, is made once for every canvas and
	kept until its bitmap is disposed; a `gpuOnly` bitmap's pixels are
	freed once it is made. The layer is rendered at `SUPERSAMPLE` times
	the screen's pixels where they are coarser than two a layout unit.
**/
class ScenePainter {
	/** Layer pixels to a target pixel, each way: the antialiasing. **/
	public static inline var SUPERSAMPLE = 2;

	/** The largest layer, each way, in pixels. **/
	static inline var MAX_LAYER = 4096;

	static inline var DEPTH_FORMAT = TextureFormat.Depth24plus;

	final layers:Array<SceneLayer> = [];
	final meshes = new haxe.ds.ObjectMap<MeshData, {vertices:GpuBuffer, indices:GpuBuffer, used:Int}>();
	final materials = new haxe.ds.ObjectMap<Material, {group:GpuBindGroup, used:Int, buffers:Int, environment:Int, textures:Int}>();
	/** A black cube, bound where a scene has no environment. **/
	static var noEnvironment:Null<Uploaded> = null;

	static var environmentSampler:Null<GpuSampler> = null;

	/** Pipelines, by shader, culling and blending. **/
	final pipelines = new Map<String, GpuPipeline>();
	var defaults:Null<{white:Uploaded, flat:Uploaded}> = null;
	var sampler:Null<GpuSampler> = null;
	var layerSampler:Null<GpuSampler> = null;
	var sceneBuffer:Null<GpuBuffer> = null;
	var drawBuffer:Null<GpuBuffer> = null;
	var drawCapacity = 0;

	/** Counts the buffers made; a material group made for older ones is made again. **/
	var buffers = 0;

	var frameCount = 0;

	final repaint:Void->Void;

	/** Seconds a canvas goes unpainted, scrolled away or hidden, before its layers are freed; drawn again, they are made again. **/
	public static var idleRelease = 1.0;

	/** Every painter with layers to free, and the frame each was last painted in. **/
	static final live:Array<ScenePainter> = [];

	static var frameNumber = 0;
	static var sweepQueued = false;
	var paintedFrame = -1;
	var paintedAt = 0.0;

	/** `repaint` asks for the canvas to be drawn again, as textures are replaced by their compressed versions. **/
	public function new(repaint:Void->Void) {
		this.repaint = repaint;
		MeshTextures.repaints.push(repaint);
		live.push(this);
	}

	/**
		After each frame the renderer draws: frees the layers of painters not
		painted for `idleRelease` seconds, and checks again after that long
		for those not painted in this frame. A canvas painted every frame it
		is drawn schedules nothing.
	**/
	public static function sweep():Void {
		release(frameNumber);
		frameNumber++;
	}

	/** Frees the layers of painters idle long enough and not painted in frame `frame`; checks again later for the rest. **/
	static function release(frame:Int):Void {
		var now = haxe.Timer.stamp(), waiting = false;
		for (p in live) {
			if (p.paintedFrame == frame || !p.holdsLayers())
				continue;
			if (now - p.paintedAt >= idleRelease)
				p.releaseLayers();
			else
				waiting = true;
		}
		if (waiting && !sweepQueued) {
			sweepQueued = true;
			// Against the last frame drawn: a painter painted in it is in view.
			ashui.animation.AnimationScheduler.main.after(idleRelease, () -> {
				sweepQueued = false;
				release(frameNumber - 1);
			});
		}
	}

	/** Bytes the layers of every painter hold on the GPU: colour and depth, four bytes a pixel each. **/
	public static function layerBytes():Int {
		var total = 0;
		for (p in live)
			for (l in p.layers)
				if (l.color != null)
					total += l.width * l.height * 8;
		return total;
	}

	function holdsLayers():Bool {
		for (l in layers)
			if (l.color != null)
				return true;
		return false;
	}

	function releaseLayers():Void
		for (l in layers) {
			l.destroy();
			l.width = l.height = 0;
			l.madeFor = null;
		}

	/** Called once a canvas frame, before its runs: what was drawn last frame and not since is freed. **/
	public function beginFrame():Void {
		frameCount++;
		loadingNow = false;
	}

	/** Whether some mesh it drew last waits for its textures. **/
	public var loading(default, null) = false;

	var loadingNow = false;

	/** Called with `loading` as it changes, on the main thread after the frame. **/
	public var onLoading:Bool->Void = _ -> {};

	function texturesReady(frame:CanvasFrame, mesh:MeshData):Bool {
		var m = mesh.material;
		for (pair in [
			{b: m.baseColorTexture, r: MeshTextures.TextureRole.Color},
			{b: m.emissiveTexture, r: MeshTextures.TextureRole.Color},
			{b: m.metallicRoughnessTexture, r: MeshTextures.TextureRole.Data},
			{b: m.occlusionTexture, r: MeshTextures.TextureRole.Occlusion},
			{b: m.normalTexture, r: MeshTextures.TextureRole.Normal}
		])
			if (pair.b != null && MeshTextures.get(frame.device, pair.b, pair.r) == null)
				return false;
		return true;
	}

	/** After the canvas's runs: frees meshes, materials and textures no run drew this frame. **/
	public function endFrame():Void {
		if (loadingNow != loading) {
			loading = loadingNow;
			// Told after the frame: a signal set while painting would change what is being drawn.
			var now = loading, report = onLoading;
			ashui.animation.AnimationScheduler.main.after(0, () -> report(now));
		}
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
		MeshTextures.endFrame();
	}

	/** Draws run `index` of the canvas's 3D runs, `draws` seen as `scene` says, over the canvas's box. **/
	public function draw(frame:CanvasFrame, index:Int, draws:Array<SceneDraw>, passes:Array<ashui.draw3d.ScenePass>, scene:Scene3D):Void {
		paintedFrame = frameNumber;
		paintedAt = haxe.Timer.stamp();
		while (layers.length <= index)
			layers.push(new SceneLayer());
		var layer = layers[index];
		var ss = frame.pixelRatio >= 2 ? 1 : SUPERSAMPLE;
		var w = Std.int(Math.min(MAX_LAYER, Math.max(1, Math.ceil(frame.width * frame.scale * ss))));
		var h = Std.int(Math.min(MAX_LAYER, Math.max(1, Math.ceil(frame.height * frame.scale * ss))));
		var resized = w != layer.width || h != layer.height || layer.color == null;
		if (resized) {
			layer.destroy();
			makeLayer(frame, layer, w, h);
		}
		// Resources are marked used whether or not the layer is rendered again, so they outlive a frame that only composites.
		// A mesh whose textures are still on their way is held back, rather than drawn plain.
		var waiting = false;
		for (d in draws)
			if (!markUsed(frame, d.mesh))
				waiting = true;
		if (waiting)
			draws = [for (d in draws) if (texturesReady(frame, d.mesh)) d];
		loadingNow = loadingNow || waiting;
		// A pass that changes every frame has the scene drawn again each frame, not kept.
		var animated = false;
		for (p in passes)
			if (p.animated())
				animated = true;
		if (resized || animated || layer.madeFor != draws || layer.textures != MeshTextures.revision) {
			render(frame, layer, draws, passes, scene);
			layer.madeFor = draws;
			layer.textures = MeshTextures.revision;
		}
		composite(frame, layer);
	}

	/** Frees every layer and upload. **/
	public function dispose():Void {
		MeshTextures.repaints.remove(repaint);
		live.remove(this);
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

	/** Keeps `mesh` and its textures for this frame; whether every texture it has is on the GPU yet. **/
	function markUsed(frame:CanvasFrame, mesh:MeshData):Bool {
		upload(frame, mesh).used = frameCount;
		var m = mesh.material;
		var group = materials.get(m);
		if (group != null)
			group.used = frameCount;
		var ready = true;
		inline function want(b:Null<Bitmap>, role:MeshTextures.TextureRole)
			if (b != null && MeshTextures.get(frame.device, b, role) == null)
				ready = false;
		want(m.baseColorTexture, Color);
		want(m.emissiveTexture, Color);
		want(m.metallicRoughnessTexture, Data);
		want(m.occlusionTexture, Occlusion);
		want(m.normalTexture, Normal);
		return ready;
	}

	function render(frame:CanvasFrame, layer:SceneLayer, draws:Array<SceneDraw>, passes:Array<ashui.draw3d.ScenePass>, scene:Scene3D):Void {
		var device = frame.device;
		ensureBuffers(frame, draws.length);
		var aspect = frame.width / Math.max(frame.height, 0.0001);
		var view = scene.camera.view(), projection = scene.camera.projection(aspect);
		var viewProjection = projection.mul(view);
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
		// Passes of the opaque and transparent stages go after the opaque meshes, before the first blended one.
		var firstBlended = order.length;
		for (slot in 0...order.length)
			if (blended(order[slot])) {
				firstBlended = slot;
				break;
			}
		var bg = scene.background, ba = scene.backgroundAlpha;
		var black = blackCube(frame);
		frame.suspend(encoder -> {
			var passFrame = new ScenePassFrame(device, encoder, frame.format, DEPTH_FORMAT, layer.width, layer.height, scene, view, projection, sceneBuffer,
				black.view, environmentSampler);
			// The lighting first: what it puts on the GPU, its environment, is what the scene and the meshes bind.
			var lighting = scene.lighting;
			lighting.prepare(passFrame);
			var environment = lighting.environment();
			if (environment != null)
				passFrame.environment = environment.view;
			device.queue().writeBuffer(sceneBuffer, 0, sceneBytes(scene, viewProjection, environment), ashui.shaders.Scene.ROWS * 16);
			var groups = [for (i in order) materialGroup(frame, draws[i].mesh.material, passFrame.environment)];
			inline function stage(at:ashui.draw3d.ScenePass.SceneStage)
				for (p in passes)
					if (p.stage() == at)
						p.draw(passFrame);
			for (p in passes)
				p.prepare(passFrame);
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
			stage(Background);
			for (slot in 0...order.length + 1) {
				if (slot == firstBlended) {
					stage(Opaque);
					stage(Transparent);
				}
				if (slot == order.length)
					break;
				var d = draws[order[slot]];
				var gpu = meshes.get(d.mesh);
				encoder.renderSetPipeline(pipeline(frame, d.mesh.material, d.opacity));
				encoder.renderSetBindGroup(0, groups[slot]);
				encoder.renderSetVertexBuffer(0, gpu.vertices);
				encoder.renderSetIndexBufferRange(gpu.indices, Uint32, 0, d.mesh.indexCount * 4);
				encoder.renderDrawIndexedRange(d.mesh.indexCount, 1, 0, 0, slot);
			}
			stage(Overlay);
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
		var wgsl = material.shader != null ? material.shader : MeshShader.WGSL;
		var key = '${(material.doubleSided ? 1 : 0) | (blended ? 2 : 0)}' + wgsl;
		var made = pipelines.get(key);
		if (made != null)
			return made;
		made = buildPipeline(frame, wgsl, material.doubleSided, blended, sharedLayout(frame));
		pipelines.set(key, made);
		return made;
	}

	/** The one binding layout every mesh pipeline has, so a material's group binds under any of them. **/
	var meshLayout:Null<gpu.GpuPipelineLayout> = null;

	/**
		Every binding the mesh shader declares, by the numbers HXSL gave
		them: an inferred layout holds only those a shader reads, fewer for a
		shader extending it that reads less.
	**/
	function sharedLayout(frame:CanvasFrame):gpu.GpuPipelineLayout {
		if (meshLayout == null) {
			var both = gpu.ShaderStage.VERTEX | gpu.ShaderStage.FRAGMENT;
			var entries = new gpu.GpuBindGroupLayoutDescriptor();
			function texture(binding:Int, dimension:gpu.TextureViewDimension) {
				var t = new gpu.GpuTextureBindingLayout();
				t.sampleType(Float);
				t.viewDimension(dimension);
				var e = new gpu.GpuBindGroupLayoutEntry(binding, both);
				e.texture(t);
				entries.addEntries(e);
				var sampled = new gpu.GpuSamplerBindingLayout();
				sampled.type(Filtering);
				var s = new gpu.GpuBindGroupLayoutEntry(binding + 1, both);
				s.sampler(sampled);
				entries.addEntries(s);
			}
			function buffer(binding:Int) {
				var b = new gpu.GpuBufferBindingLayout();
				b.type(ReadOnlyStorage);
				var e = new gpu.GpuBindGroupLayoutEntry(binding, both);
				e.buffer(b);
				entries.addEntries(e);
			}
			for (binding in [
				MeshShader.TEXTURE_baseColorMap,
				MeshShader.TEXTURE_normalMap,
				MeshShader.TEXTURE_metalRoughMap,
				MeshShader.TEXTURE_emissiveMap,
				MeshShader.TEXTURE_occlusionMap
			])
				texture(binding, D2d);
			texture(MeshShader.TEXTURE_environmentMap, Cube);
			buffer(MeshShader.BUFFER_scene);
			buffer(MeshShader.BUFFER_draws);
			var descriptor = new gpu.GpuPipelineLayoutDescriptor();
			descriptor.addBindGroupLayouts(frame.device.createBindGroupLayout(entries));
			meshLayout = frame.device.createPipelineLayout(descriptor);
		}
		return meshLayout;
	}

	function buildPipeline(frame:CanvasFrame, wgsl:String, doubleSided:Bool, blended:Bool, layout:Null<gpu.GpuPipelineLayout>):GpuPipeline {
		var device = frame.device;
		var builder = device.pipeline();
		builder.shader(device.createShader(wgsl), "vertex", "fragment");
		if (layout != null)
			builder.layout(layout);
		builder.vertexBuffer(MeshData.STRIDE, Vertex);
		builder.attribute(Float32x3, MeshData.POSITION_OFFSET, MeshShader.INPUT_position);
		builder.attribute(Float32x3, MeshData.NORMAL_OFFSET, MeshShader.INPUT_normal);
		builder.attribute(Float32x2, MeshData.UV_OFFSET, MeshShader.INPUT_uv);
		builder.attribute(Float32x4, MeshData.TANGENT_OFFSET, MeshShader.INPUT_tangent);
		builder.target(frame.format, GpuFlags.COLOR_WRITE_ALL);
		// Premultiplied into the layer, as it is composited.
		builder.blend(SrcAlpha, OneMinusSrcAlpha, Add, One, OneMinusSrcAlpha, Add);
		builder.depth(DEPTH_FORMAT, !blended, Less);
		builder.primitive(TriangleList, doubleSided ? None : Back, Ccw);
		return builder.build();
	}


	/** Its textures, the environment, the scene and the draws: a material's bind group, made for its pipeline. **/
	function materialGroup(frame:CanvasFrame, material:Material, environment:GpuTextureView):GpuBindGroup {
		var known = materials.get(material);
		if (known != null && known.buffers == buffers && known.environment == (environment : Int) && known.textures == MeshTextures.revision) {
			known.used = frameCount;
			return known.group;
		}
		if (known != null)
			known.group.destroy();
		var d = ensureDefaults(frame);
		// A texture still being compressed is drawn as the default until it is in place.
		function tex(b:Null<Bitmap>, role:MeshTextures.TextureRole, fallback:Uploaded):GpuTextureView {
			var t = b != null ? MeshTextures.get(frame.device, b, role) : null;
			return t != null ? t.view : fallback.view;
		}
		var bindings = new GpuBindings();
		for (view in [
			tex(material.baseColorTexture, Color, d.white),
			tex(material.normalTexture, Normal, d.flat),
			tex(material.metallicRoughnessTexture, Data, d.white),
			tex(material.emissiveTexture, Color, d.white),
			tex(material.occlusionTexture, Occlusion, d.white)
		]) {
			bindings.texture(view);
			bindings.sampler(sampler);
		}
		bindings.texture(environment);
		bindings.sampler(environmentSampler);
		bindings.buffer(sceneBuffer);
		bindings.buffer(drawBuffer);
		// Under the shared layout: the default pipeline's group binds under an extension's too.
		var group = frame.device.bindGroup(pipeline(frame, Material.DEFAULT, 1), 0, bindings);
		bindings.destroy();
		materials.set(material, {group: group, used: frameCount, buffers: buffers, environment: (environment : Int), textures: MeshTextures.revision});
		return group;
	}

	/** A black cube with its sampler, bound where a scene's lighting has no environment. **/
	function blackCube(frame:CanvasFrame):Uploaded {
		var device = frame.device;
		if (environmentSampler == null) {
			var s = new GpuSamplerDescriptor();
			s.magFilter(Linear);
			s.minFilter(Linear);
			s.mipmapFilter(Linear);
			environmentSampler = device.sampler(s);
		}
		if (noEnvironment == null) {
			var extent = new GpuExtent3D(1);
			extent.height(1);
			extent.depthOrArrayLayers(6);
			var t = device.texture(new GpuTextureDescriptor(extent, TextureFormat.Rgba16float, GpuFlags.TEXTURE_BINDING | GpuFlags.TEXTURE_COPY_DST));
			var destination = new GpuTexelCopyTextureInfo(t);
			var layout = new GpuTexelCopyBufferLayout();
			layout.bytesPerRow(8);
			layout.rowsPerImage(1);
			device.queue().writeTextureWith(destination, haxe.io.Bytes.alloc(6 * 8), layout, extent);
			var view = new GpuTextureViewDescriptor();
			view.dimension(Cube);
			noEnvironment = {texture: t, view: t.createView(view)};
		}
		return noEnvironment;
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

	static function linear(c:Int):Float {
		var v = c / 255;
		return v <= 0.04045 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4);
	}

	static function sceneBytes(scene:Scene3D, viewProjection:Mat4, environment:Null<ashui.draw3d.SceneLighting.EnvironmentMap>):haxe.io.Bytes {
		var out = haxe.io.Bytes.alloc(ashui.shaders.Scene.ROWS * 16);
		viewProjection.write(out, 0);
		var lighting = scene.lighting;
		var lights = lighting.lights().slice(0, ashui.shaders.Scene.MAX_LIGHTS);
		var eye = scene.camera.eye;
		row(out, 4, eye.x, eye.y, eye.z, lights.length);
		var a = lighting.ambientColor(), s = lighting.ambientStrength();
		row(out, 5, linear(a >> 16 & 0xff) * s, linear(a >> 8 & 0xff) * s, linear(a & 0xff) * s, scene.exposure);
		if (environment != null)
			row(out, 6, environment.intensity, environment.levels - 1, 1, 0);
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
