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

/** A mesh drawn in a run of 3D draws: where, how opaque, and in which material, its own unless the draw gave another. **/
typedef SceneDraw = {mesh:MeshData, transform:Mat4, opacity:Float, material:Material};

/** A texture on the GPU and its view. **/
private typedef Uploaded = {texture:GpuTexture, view:GpuTextureView};

/** One level of a layer's bloom chain. It holds the level's texture and the settings and bind groups for the passes into it (down) and out of it (up). **/
private class BloomLevel {
	public final width:Int;
	public final height:Int;
	public final texture:GpuTexture;
	public final view:GpuTextureView;
	public final downSettings:gpu.GpuBuffer;
	public final upSettings:gpu.GpuBuffer;
	public var downGroup:Null<GpuBindGroup> = null;
	public var upGroup:Null<GpuBindGroup> = null;

	public function new(device:gpu.GpuDevice, width:Int, height:Int) {
		this.width = width;
		this.height = height;
		var size = new GpuExtent3D(width);
		size.height(height);
		texture = device.texture(new GpuTextureDescriptor(size, Rgba16float, GpuFlags.TEXTURE_RENDER_ATTACHMENT | GpuFlags.TEXTURE_BINDING));
		view = texture.createView(new GpuTextureViewDescriptor());
		downSettings = device.createBuffer(new GpuBufferDescriptor(16, GpuFlags.BUFFER_STORAGE | GpuFlags.BUFFER_COPY_DST));
		upSettings = device.createBuffer(new GpuBufferDescriptor(16, GpuFlags.BUFFER_STORAGE | GpuFlags.BUFFER_COPY_DST));
	}

	public function destroy():Void {
		if (downGroup != null)
			downGroup.destroy();
		if (upGroup != null)
			upGroup.destroy();
		downSettings.destroy();
		upSettings.destroy();
		view.destroy();
		texture.destroy();
	}
}

/** Where one run of a canvas's 3D draws is rendered, and what it was rendered for. **/
private class SceneLayer {
	public var color:Null<GpuTexture> = null;
	public var colorView:Null<GpuTextureView> = null;
	public var depth:Null<GpuTexture> = null;
	public var depthView:Null<GpuTextureView> = null;
	public var group:Null<GpuBindGroup> = null;
	public var groupPipeline:Null<GpuPipeline> = null;

	/** The texture view the composite's bind group samples: the layer itself, or the fish-eye's output. **/
	public var groupView:Null<GpuTextureView> = null;

	/** For a fish-eye lens: the texture the bent layer is drawn into, with its settings buffer and bind group. **/
	/** For bloom: a half-float texture holding the scene's glowing light, as the glow pass draws it. **/
	public var glow:Null<GpuTexture> = null;
	public var glowView:Null<GpuTextureView> = null;

	public var lensColor:Null<GpuTexture> = null;
	public var lensView:Null<GpuTextureView> = null;
	public var lensGroup:Null<GpuBindGroup> = null;
	public var lensSettings:Null<gpu.GpuBuffer> = null;
	public var lens = 0.0;

	/** The bloom chain's levels. The first is half the layer's size, and each further level is half the one before. **/
	public final bloomLevels:Array<BloomLevel> = [];
	public var bloomAdd:Null<{settings:gpu.GpuBuffer, group:GpuBindGroup}> = null;
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
		if (lensGroup != null)
			lensGroup.destroy();
		if (lensView != null)
			lensView.destroy();
		if (lensColor != null)
			lensColor.destroy();
		if (lensSettings != null)
			lensSettings.destroy();
		if (glowView != null)
			glowView.destroy();
		if (glow != null)
			glow.destroy();
		glow = null;
		glowView = null;
		for (l in bloomLevels)
			l.destroy();
		bloomLevels.resize(0);
		if (bloomAdd != null) {
			bloomAdd.group.destroy();
			bloomAdd.settings.destroy();
			bloomAdd = null;
		}
		group = null;
		color = null;
		depth = null;
		lensGroup = null;
		lensView = null;
		lensColor = null;
		lensSettings = null;
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
	final materials = new haxe.ds.ObjectMap<Material, {group:GpuBindGroup, used:Int, buffers:Int, environment:Int, shadow:Int, textures:Int}>();

	/** Each masked or blended material's group for the shadow pass, its base colour bound for the cutout. **/
	final cutouts = new haxe.ds.ObjectMap<Material, {group:GpuBindGroup, used:Int, buffers:Int, textures:Int}>();
	/** A black cube, bound where a scene has no environment. **/
	static var noEnvironment:Null<Uploaded> = null;

	static var environmentSampler:Null<GpuSampler> = null;

	/** Pipelines, by shader, culling and blending. **/
	/** Each shader's pipelines, by its WGSL string's identity: single-sided or double, opaque or blended. **/
	final pipelines = new haxe.ds.ObjectMap<String, Array<Null<GpuPipeline>>>();
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

	/** Called after each frame in which it rendered a scene afresh, rather than showing what it rendered before. **/
	public var onRendered:Void->Void = () -> {};

	var renderedNow = false;

	function texturesReady(frame:CanvasFrame, m:Material):Bool {
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
		if (renderedNow) {
			renderedNow = false;
			onRendered();
		}
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
		for (m => g in cutouts)
			if (g.used != frameCount) {
				g.group.destroy();
				cutouts.remove(m);
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
		var ss:Float = frame.pixelRatio >= 2 ? 1 : SUPERSAMPLE;
		// A fish-eye magnifies the centre of a wider view, so the layer is rendered at up to twice the resolution to keep the centre sharp.
		if (scene.lens > 0)
			ss = Math.max(ss, Math.min(2, 1 + scene.lens * 2));
		layer.lens = scene.lens;
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
			if (!markUsed(frame, d.mesh, d.material))
				waiting = true;
		if (waiting)
			draws = [for (d in draws) if (texturesReady(frame, d.material)) d];
		loadingNow = loadingNow || waiting;
		// A pass that changes every frame has the scene drawn again each frame, not kept.
		var animated = false;
		for (p in passes)
			if (p.animated())
				animated = true;
		if (resized || animated || layer.madeFor != draws || layer.textures != MeshTextures.revision) {
			render(frame, layer, draws, passes, scene);
			renderedNow = true;
			layer.madeFor = draws;
			layer.textures = MeshTextures.revision;
		}
		composite(frame, layer);
	}

	/** Frees every layer and upload. **/
	public function dispose():Void {
		MeshTextures.repaints.remove(repaint);
		live.remove(this);
		for (t in [shadowColor, shadowDepth])
			if (t != null) {
				t.view.destroy();
				t.texture.destroy();
			}
		shadowColor = shadowDepth = null;
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
	function markUsed(frame:CanvasFrame, mesh:MeshData, m:Material):Bool {
		upload(frame, mesh).used = frameCount;
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
		var aspect = frame.width / Math.max(frame.height, 0.0001);
		// A fish-eye renders a wider view, so the edges have more to compress and the centre keeps the camera's own scale.
		var camera = scene.camera;
		if (scene.lens > 0)
			camera = camera.with(null, null, 2 * Math.atan(Math.tan(camera.fovY / 2) * (1 + scene.lens * (aspect * aspect + 1))));
		var view = camera.view(), projection = camera.projection(aspect);
		var viewProjection = projection.mul(view);
		// A blended material at full opacity is drawn in two halves: its solid fragments with the opaque meshes,
		// writing depth, so a shell its exporter marked blended hides what is inside it; then the rest, blended.
		// Each entry is a draw's index times two, plus one for a solid half.
		var entries = [];
		for (i in 0...draws.length) {
			entries.push(i * 2);
			if (draws[i].material.alphaMode == Blend && draws[i].opacity >= 1)
				entries.push(i * 2 + 1);
		}
		ensureBuffers(frame, entries.length);
		var eye = scene.camera.eye;
		inline function blendedEntry(e:Int)
			return e & 1 == 0 && (draws[e >> 1].material.alphaMode == Blend || draws[e >> 1].opacity < 1);
		inline function distance(i:Int)
			return draws[i].transform.transformPoint(draws[i].mesh.min.lerp(draws[i].mesh.max, 0.5)).distance(eye);
		// Opaque first, in order; then blended, furthest first, so each blends over what is behind it.
		entries.sort((a, b) -> {
			var ba = blendedEntry(a), bb = blendedEntry(b);
			if (ba != bb)
				return ba ? 1 : -1;
			if (!ba)
				return a - b;
			var da = distance(a >> 1), db = distance(b >> 1);
			return da > db ? -1 : da < db ? 1 : 0;
		});
		var order = [for (e in entries) e >> 1];
		var solid = [for (e in entries) e & 1 == 1];
		var bytes = haxe.io.Bytes.alloc(entries.length * ashui.shaders.MeshDraw.ROWS * 16);
		for (slot in 0...order.length)
			writeDraw(bytes, slot * ashui.shaders.MeshDraw.ROWS * 16, draws[order[slot]], solid[slot]);
		device.queue().writeBuffer(drawBuffer, 0, bytes, bytes.length);
		// Passes of the opaque and transparent stages go after the opaque meshes, before the first blended one.
		var firstBlended = order.length;
		for (slot in 0...entries.length)
			if (blendedEntry(entries[slot])) {
				firstBlended = slot;
				break;
			}
		var bg = scene.background, ba = scene.backgroundAlpha;
		var black = blackCube(frame);
		var far = noShadow(frame);
		var bounds = sceneBounds(draws);
		frame.suspend(encoder -> {
			var passFrame = new ScenePassFrame(device, encoder, frame.format, DEPTH_FORMAT, layer.width, layer.height, scene, view, projection, sceneBuffer,
				black.view, environmentSampler, bounds, far.view, shadowSampler);
			// The lighting first: what it puts on the GPU, its environment and its shadows, is what the scene and the meshes bind.
			var lighting = scene.lighting;
			lighting.prepare(passFrame);
			var environment = lighting.environment();
			if (environment != null)
				passFrame.environment = environment.view;
			var shadows = lighting.shadows();
			if (shadows != null)
				passFrame.shadowMap = shadowTarget(frame, shadows.size).view;
			device.queue().writeBuffer(sceneBuffer, 0, sceneBytes(scene, viewProjection, environment, shadows, order.length), ashui.shaders.Scene.ROWS * 16);
			inline function stage(at:ashui.draw3d.ScenePass.SceneStage)
				for (p in passes)
					if (p.stage() == at)
						p.draw(passFrame);
			for (p in passes)
				p.prepare(passFrame);
			if (shadows != null)
				drawShadows(frame, encoder, passFrame, draws, order, solid, passes);
			var groups = [for (i in order) materialGroup(frame, draws[i].material, passFrame.environment, passFrame.shadowMap)];
			var color = new GpuRenderPassColorAttachment(Clear, Store);
			color.viewTextureView(layer.colorView);
			// Premultiplied, as the layer is composited.
			color.clearValue(new GpuColor((bg >> 16 & 0xff) / 255 * ba, (bg >> 8 & 0xff) / 255 * ba, (bg & 0xff) / 255 * ba, ba));
			var depth = new GpuRenderPassDepthStencilAttachment();
			depth.viewTextureView(layer.depthView);
			depth.depthClearValue(1);
			depth.depthLoadOp(Clear);
			// The glow pass tests against this depth, so it is kept when there is bloom.
			var glowing = scene.bloom != null && scene.bloom.strength > 0;
			depth.depthStoreOp(glowing ? Store : Discard);
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
				encoder.renderSetPipeline(pipeline(frame, d.material, slot >= firstBlended));
				encoder.renderSetBindGroup(0, groups[slot]);
				encoder.renderSetVertexBuffer(0, gpu.vertices);
				encoder.renderSetIndexBufferRange(gpu.indices, Uint32, 0, d.mesh.indexCount * 4);
				encoder.renderDrawIndexedRange(d.mesh.indexCount, 1, 0, 0, slot);
			}
			stage(Overlay);
			encoder.renderEnd();
			if (glowing) {
				drawGlow(frame, encoder, layer, draws, order, groups, firstBlended, passes, passFrame);
				glow(frame, encoder, layer, scene.bloom);
			}
			if (scene.lens > 0)
				bend(frame, encoder, layer, scene.lens);
		});
	}

	var lensPipeline:Null<GpuPipeline> = null;
	var bloomDown:Null<GpuPipeline> = null;

	/**
		The glow pass. It draws each opaque mesh a second time, with its own
		material's shader, into the layer's glow texture, testing against the
		depth the scene left so that only visible surfaces glow. The instance
		index is raised by the draw count, which tells the mesh shader to write
		untone-mapped light. Then each `GlowCaster` pass draws its own glow.
	**/
	function drawGlow(frame:CanvasFrame, encoder:gpu.GpuEncoder, layer:SceneLayer, draws:Array<SceneDraw>, order:Array<Int>,
			groups:Array<GpuBindGroup>, firstBlended:Int, passes:Array<ashui.draw3d.ScenePass>, passFrame:ScenePassFrame):Void {
		var device = frame.device;
		if (layer.glow == null) {
			var size = new GpuExtent3D(layer.width);
			size.height(layer.height);
			layer.glow = device.texture(new GpuTextureDescriptor(size, Rgba16float, GpuFlags.TEXTURE_RENDER_ATTACHMENT | GpuFlags.TEXTURE_BINDING));
			layer.glowView = layer.glow.createView(new GpuTextureViewDescriptor());
		}
		var color = new GpuRenderPassColorAttachment(Clear, Store);
		color.viewTextureView(layer.glowView);
		color.clearValue(new GpuColor(0, 0, 0, 0));
		var depth = new GpuRenderPassDepthStencilAttachment();
		depth.viewTextureView(layer.depthView);
		depth.depthLoadOp(Load);
		depth.depthStoreOp(Discard);
		var pass = new GpuRenderPassDescriptor();
		pass.addColorAttachments(color);
		pass.depthStencilAttachment(depth);
		encoder.beginRenderPass(pass);
		for (slot in 0...firstBlended) {
			var d = draws[order[slot]];
			if (d.material.unlit)
				continue;
			var gpu = meshes.get(d.mesh);
			encoder.renderSetPipeline(glowPipeline(frame, d.material));
			encoder.renderSetBindGroup(0, groups[slot]);
			encoder.renderSetVertexBuffer(0, gpu.vertices);
			encoder.renderSetIndexBufferRange(gpu.indices, Uint32, 0, d.mesh.indexCount * 4);
			encoder.renderDrawIndexedRange(d.mesh.indexCount, 1, 0, 0, slot + order.length);
		}
		for (p in passes)
			if (Std.isOfType(p, ashui.draw3d.ScenePass.GlowCaster))
				(cast p : ashui.draw3d.ScenePass.GlowCaster).drawGlow(passFrame);
		encoder.renderEnd();
	}
	var bloomUp:Null<GpuPipeline> = null;
	var bloomOnto:Null<GpuPipeline> = null;

	/**
		Runs bloom. The bright parts of the glow texture are halved into the
		chain's first level, and each further level halves the one before,
		down to a few dozen pixels. Then each level is doubled and added onto
		the one above it, and the first level is added onto the layer.
	**/
	function glow(frame:CanvasFrame, encoder:gpu.GpuEncoder, layer:SceneLayer, bloom:ashui.draw3d.Bloom):Void {
		var device = frame.device;
		if (bloomDown == null) {
			function made(format:TextureFormat, add:Bool, keepAlpha:Bool):GpuPipeline {
				var builder = device.pipeline();
				builder.shader(device.createShader(BloomShader.WGSL), "vertex", "fragment");
				builder.target(format, GpuFlags.COLOR_WRITE_ALL);
				if (add)
					builder.blend(One, One, Add, keepAlpha ? Zero : One, One, Add);
				builder.primitive(TriangleList, None, Ccw);
				return builder.build();
			}
			bloomDown = made(Rgba16float, false, false);
			bloomUp = made(Rgba16float, true, false);
			bloomOnto = made(frame.format, true, true);
		}
		var sampler = compositeSampler(frame);
		inline function group(pipeline:GpuPipeline, source:GpuTextureView, settings:gpu.GpuBuffer):GpuBindGroup {
			var bindings = new GpuBindings();
			bindings.texture(source);
			bindings.sampler(sampler);
			bindings.buffer(settings);
			var g = device.bindGroup(pipeline, 0, bindings);
			bindings.destroy();
			return g;
		}
		if (layer.bloomLevels.length == 0) {
			var w = layer.width >> 1, h = layer.height >> 1;
			while (w >= 16 && h >= 16 && layer.bloomLevels.length < 6) {
				layer.bloomLevels.push(new BloomLevel(device, w, h));
				w >>= 1;
				h >>= 1;
			}
			var levels = layer.bloomLevels;
			for (i in 0...levels.length) {
				levels[i].downGroup = group(bloomDown, i == 0 ? layer.glowView : levels[i - 1].view, levels[i].downSettings);
				if (i > 0)
					levels[i].upGroup = group(bloomUp, levels[i].view, levels[i].upSettings);
			}
			var settings = device.createBuffer(new GpuBufferDescriptor(16, GpuFlags.BUFFER_STORAGE | GpuFlags.BUFFER_COPY_DST));
			layer.bloomAdd = {settings: settings, group: group(bloomOnto, levels[0].view, settings)};
		}
		var levels = layer.bloomLevels;
		if (levels.length == 0)
			return;
		var b = haxe.io.Bytes.alloc(16);
		function settings(buffer:gpu.GpuBuffer, tx:Float, ty:Float, step:Int, value:Float) {
			b.setFloat(0, tx);
			b.setFloat(4, ty);
			b.setFloat(8, step);
			b.setFloat(12, value);
			device.queue().writeBuffer(buffer, 0, b, 16);
		}
		function pass(target:GpuTextureView, load:Bool, pipeline:GpuPipeline, g:GpuBindGroup) {
			var color = new GpuRenderPassColorAttachment(load ? Load : Clear, Store);
			color.viewTextureView(target);
			color.clearValue(new GpuColor(0, 0, 0, 0));
			var p = new GpuRenderPassDescriptor();
			p.addColorAttachments(color);
			encoder.beginRenderPass(p);
			encoder.renderSetPipeline(pipeline);
			encoder.renderSetBindGroup(0, g);
			encoder.renderDraw(3, 1);
			encoder.renderEnd();
		}
		// Down: each level is made from the one above it; the first keeps only what passes the threshold.
		for (i in 0...levels.length) {
			var srcW = i == 0 ? layer.width : levels[i - 1].width, srcH = i == 0 ? layer.height : levels[i - 1].height;
			settings(levels[i].downSettings, 1 / srcW, 1 / srcH, i == 0 ? 0 : 1, bloom.threshold);
			pass(levels[i].view, false, bloomDown, levels[i].downGroup);
		}
		// Up: each level is doubled and added onto the one above it, starting from the smallest.
		var i = levels.length - 1;
		while (i > 0) {
			settings(levels[i].upSettings, 1 / levels[i - 1].width, 1 / levels[i - 1].height, 2, 0);
			pass(levels[i - 1].view, true, bloomUp, levels[i].upGroup);
			i--;
		}
		settings(layer.bloomAdd.settings, 0, 0, 3, bloom.strength);
		pass(layer.colorView, true, bloomOnto, layer.bloomAdd.group);
	}

	/** Applies the fish-eye lens: bends the rendered layer into the layer's lens texture. `strength` is `Scene3D.lens`. **/
	function bend(frame:CanvasFrame, encoder:gpu.GpuEncoder, layer:SceneLayer, strength:Float):Void {
		var device = frame.device;
		if (lensPipeline == null) {
			var builder = device.pipeline();
			builder.shader(device.createShader(LensShader.WGSL), "vertex", "fragment");
			builder.target(frame.format, GpuFlags.COLOR_WRITE_ALL);
			builder.primitive(TriangleList, None, Ccw);
			lensPipeline = builder.build();
		}
		if (layer.lensColor == null) {
			var size = new GpuExtent3D(layer.width);
			size.height(layer.height);
			layer.lensColor = device.texture(new GpuTextureDescriptor(size, frame.format, GpuFlags.TEXTURE_RENDER_ATTACHMENT | GpuFlags.TEXTURE_BINDING));
			layer.lensView = layer.lensColor.createView(new GpuTextureViewDescriptor());
			layer.lensSettings = device.createBuffer(new GpuBufferDescriptor(16, GpuFlags.BUFFER_STORAGE | GpuFlags.BUFFER_COPY_DST));
			var bindings = new GpuBindings();
			bindings.texture(layer.colorView);
			bindings.sampler(compositeSampler(frame));
			bindings.buffer(layer.lensSettings);
			layer.lensGroup = device.bindGroup(lensPipeline, 0, bindings);
			bindings.destroy();
		}
		var aspect = layer.width / Math.max(1, layer.height);
		var b = haxe.io.Bytes.alloc(16);
		b.setFloat(0, strength);
		b.setFloat(4, aspect);
		b.setFloat(8, aspect * aspect + 1);
		device.queue().writeBuffer(layer.lensSettings, 0, b, 16);
		var color = new GpuRenderPassColorAttachment(Clear, Store);
		color.viewTextureView(layer.lensView);
		color.clearValue(new GpuColor(0, 0, 0, 0));
		var pass = new GpuRenderPassDescriptor();
		pass.addColorAttachments(color);
		encoder.beginRenderPass(pass);
		encoder.renderSetPipeline(lensPipeline);
		encoder.renderSetBindGroup(0, layer.lensGroup);
		encoder.renderDraw(3, 1);
		encoder.renderEnd();
	}

	/** The linear-filtering sampler used to composite, bend and bloom the layer. **/
	function compositeSampler(frame:CanvasFrame):GpuSampler {
		if (layerSampler == null) {
			var d = new GpuSamplerDescriptor();
			d.magFilter(Linear);
			d.minFilter(Linear);
			layerSampler = frame.device.sampler(d);
		}
		return layerSampler;
	}

	function composite(frame:CanvasFrame, layer:SceneLayer):Void {
		var pass = frame.bind(SceneShader.WGSL);
		// With a fish-eye lens, the composite shows the bent layer.
		var view = layer.lens > 0 && layer.lensView != null ? layer.lensView : layer.colorView;
		if (layer.group == null || layer.groupPipeline != pass.pipeline || layer.groupView != view) {
			if (layer.group != null)
				layer.group.destroy();
			var bindings = new GpuBindings();
			bindings.texture(view);
			bindings.sampler(compositeSampler(frame));
			layer.group = frame.device.bindGroup(pass.pipeline, SceneShader.TEXTURE_canvasLayer_GROUP, bindings);
			bindings.destroy();
			layer.groupPipeline = pass.pipeline;
			layer.groupView = view;
		}
		frame.encoder.renderSetBindGroup(SceneShader.TEXTURE_canvasLayer_GROUP, layer.group);
		frame.encoder.renderDrawRange(6, 1, 0, frame.record);
	}

	/** The pipeline for a material: culled unless double-sided, writing depth unless `blended`. **/
	function pipeline(frame:CanvasFrame, material:Material, blended:Bool):GpuPipeline {
		var wgsl = material.shader != null ? material.shader : MeshShader.WGSL;
		// By the shader's string itself, not its text: looked up for every draw, a shader's WGSL is too long to hash each time.
		var variants = pipelines.get(wgsl);
		if (variants == null) {
			variants = [null, null, null, null, null, null];
			pipelines.set(wgsl, variants);
		}
		var at = (material.doubleSided ? 1 : 0) | (blended ? 2 : 0);
		var made = variants[at];
		if (made == null) {
			made = buildPipeline(frame, wgsl, material.doubleSided, blended, false, sharedLayout(frame));
			variants[at] = made;
		}
		return made;
	}

	/** A material's pipeline for bloom's glow pass: into the half-float glow target, tested against the scene's depth. **/
	function glowPipeline(frame:CanvasFrame, material:Material):GpuPipeline {
		pipeline(frame, material, false);
		var wgsl = material.shader != null ? material.shader : MeshShader.WGSL;
		var variants = pipelines.get(wgsl);
		var at = 4 + (material.doubleSided ? 1 : 0);
		if (variants[at] == null)
			variants[at] = buildPipeline(frame, wgsl, material.doubleSided, false, true, sharedLayout(frame));
		return variants[at];
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
			texture(MeshShader.TEXTURE_shadowMap, D2d);
			buffer(MeshShader.BUFFER_scene);
			buffer(MeshShader.BUFFER_draws);
			var descriptor = new gpu.GpuPipelineLayoutDescriptor();
			descriptor.addBindGroupLayouts(frame.device.createBindGroupLayout(entries));
			meshLayout = frame.device.createPipelineLayout(descriptor);
		}
		return meshLayout;
	}

	function buildPipeline(frame:CanvasFrame, wgsl:String, doubleSided:Bool, blended:Bool, glow:Bool, layout:Null<gpu.GpuPipelineLayout>):GpuPipeline {
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
		if (glow) {
			// The glow pass redraws visible surfaces at the depth they left: LessEqual, no blending, no depth writes.
			builder.target(ScenePassFrame.GLOW_FORMAT, GpuFlags.COLOR_WRITE_ALL);
			builder.depth(DEPTH_FORMAT, false, LessEqual);
		} else {
			builder.target(frame.format, GpuFlags.COLOR_WRITE_ALL);
			// Premultiplied into the layer, as it is composited.
			builder.blend(SrcAlpha, OneMinusSrcAlpha, Add, One, OneMinusSrcAlpha, Add);
			builder.depth(DEPTH_FORMAT, !blended, Less);
		}
		builder.primitive(TriangleList, doubleSided ? None : Back, Ccw);
		return builder.build();
	}


	/** Its textures, the environment, the scene and the draws: a material's bind group, made for its pipeline. **/
	function materialGroup(frame:CanvasFrame, material:Material, environment:GpuTextureView, shadow:GpuTextureView):GpuBindGroup {
		var known = materials.get(material);
		if (known != null && known.buffers == buffers && known.environment == (environment : Int) && known.shadow == (shadow : Int)
			&& known.textures == MeshTextures.revision) {
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
		bindings.texture(shadow);
		bindings.sampler(shadowSampler);
		bindings.buffer(sceneBuffer);
		bindings.buffer(drawBuffer);
		// Under the shared layout: the default pipeline's group binds under an extension's too.
		var group = frame.device.bindGroup(pipeline(frame, Material.DEFAULT, false), 0, bindings);
		bindings.destroy();
		materials.set(material, {group: group, used: frameCount, buffers: buffers, environment: (environment : Int), shadow: (shadow : Int), textures: MeshTextures.revision});
		return group;
	}

	/** The box round every draw's mesh as placed. **/
	static function sceneBounds(draws:Array<SceneDraw>):{min:Vec3, max:Vec3} {
		if (draws.length == 0)
			return {min: Vec3.ZERO, max: Vec3.ZERO};
		var lo = new Vec3(Math.POSITIVE_INFINITY, Math.POSITIVE_INFINITY, Math.POSITIVE_INFINITY);
		var hi = new Vec3(Math.NEGATIVE_INFINITY, Math.NEGATIVE_INFINITY, Math.NEGATIVE_INFINITY);
		for (d in draws)
			for (x in [d.mesh.min.x, d.mesh.max.x])
				for (y in [d.mesh.min.y, d.mesh.max.y])
					for (z in [d.mesh.min.z, d.mesh.max.z]) {
						var p = d.transform.transformPoint(new Vec3(x, y, z));
						lo = new Vec3(Math.min(lo.x, p.x), Math.min(lo.y, p.y), Math.min(lo.z, p.z));
						hi = new Vec3(Math.max(hi.x, p.x), Math.max(hi.y, p.y), Math.max(hi.z, p.z));
					}
		return {min: lo, max: hi};
	}

	var shadowColor:Null<Uploaded> = null;
	var shadowDepth:Null<Uploaded> = null;
	var shadowSize = 0;
	var shadowPipeline:Null<GpuPipeline> = null;
	var cutoutPipeline:Null<GpuPipeline> = null;
	var shadowGroup:Null<GpuBindGroup> = null;
	var shadowGroupBuffers = -1;

	/** A 1×1 map holding "far", bound where a scene has no shadows: nothing is in shadow. **/
	static var noShadowMap:Null<Uploaded> = null;

	static var shadowSampler:Null<GpuSampler> = null;

	function noShadow(frame:CanvasFrame):Uploaded {
		if (shadowSampler == null) {
			var s = new GpuSamplerDescriptor();
			s.magFilter(Linear);
			s.minFilter(Linear);
			shadowSampler = frame.device.sampler(s);
		}
		if (noShadowMap == null) {
			var size = new GpuExtent3D(1);
			size.height(1);
			var t = frame.device.texture(new GpuTextureDescriptor(size, ScenePassFrame.SHADOW_FORMAT, GpuFlags.TEXTURE_BINDING | GpuFlags.TEXTURE_COPY_DST));
			// 1.0 as a 16-bit float.
			var one = haxe.io.Bytes.alloc(2);
			one.setUInt16(0, 0x3C00);
			frame.device.queue().writeTexture(t, one, 1, 1, 2);
			noShadowMap = {texture: t, view: t.createView(new GpuTextureViewDescriptor())};
		}
		return noShadowMap;
	}

	/** The shadow map, `size` square, made or remade to fit, with the depth the shadow pass tests against. **/
	function shadowTarget(frame:CanvasFrame, size:Int):Uploaded {
		size = Std.int(Math.max(16, Math.min(8192, size)));
		if (shadowColor == null || shadowSize != size) {
			for (t in [shadowColor, shadowDepth])
				if (t != null) {
					t.view.destroy();
					t.texture.destroy();
				}
			var extent = new GpuExtent3D(size);
			extent.height(size);
			var c = frame.device.texture(new GpuTextureDescriptor(extent, ScenePassFrame.SHADOW_FORMAT, GpuFlags.TEXTURE_RENDER_ATTACHMENT | GpuFlags.TEXTURE_BINDING));
			var d = frame.device.texture(new GpuTextureDescriptor(extent, ScenePassFrame.SHADOW_DEPTH_FORMAT, GpuFlags.TEXTURE_RENDER_ATTACHMENT));
			shadowColor = {texture: c, view: c.createView(new GpuTextureViewDescriptor())};
			shadowDepth = {texture: d, view: d.createView(new GpuTextureViewDescriptor())};
			shadowSize = size;
		}
		return shadowColor;
	}

	/**
		The shadow pass, into the shadow map from the light: every mesh at
		full opacity, a masked or blended one where its base colour's alpha
		makes it solid, then each pass that casts shadows. A blended mesh
		drawn in two halves casts once.
	**/
	function drawShadows(frame:CanvasFrame, encoder:gpu.GpuEncoder, passFrame:ScenePassFrame, draws:Array<SceneDraw>, order:Array<Int>,
			solid:Array<Bool>, passes:Array<ashui.draw3d.ScenePass>):Void {
		var device = frame.device;
		if (shadowPipeline == null) {
			var builder = passFrame.shadowPipelineBuilder(MeshShadowShader.WGSL);
			builder.vertexBuffer(MeshData.STRIDE, Vertex);
			builder.attribute(Float32x3, MeshData.POSITION_OFFSET, MeshShadowShader.INPUT_position);
			shadowPipeline = builder.build();
			builder = passFrame.shadowPipelineBuilder(MeshCutoutShadowShader.WGSL);
			builder.vertexBuffer(MeshData.STRIDE, Vertex);
			builder.attribute(Float32x3, MeshData.POSITION_OFFSET, MeshCutoutShadowShader.INPUT_position);
			builder.attribute(Float32x2, MeshData.UV_OFFSET, MeshCutoutShadowShader.INPUT_uv);
			cutoutPipeline = builder.build();
		}
		if (shadowGroup == null || shadowGroupBuffers != buffers) {
			if (shadowGroup != null)
				shadowGroup.destroy();
			var bindings = new GpuBindings();
			bindings.buffer(sceneBuffer);
			bindings.buffer(drawBuffer);
			shadowGroup = device.bindGroup(shadowPipeline, 0, bindings);
			bindings.destroy();
			shadowGroupBuffers = buffers;
		}
		var color = new GpuRenderPassColorAttachment(Clear, Store);
		color.viewTextureView(shadowColor.view);
		color.clearValue(new GpuColor(1, 1, 1, 1));
		var depth = new GpuRenderPassDepthStencilAttachment();
		depth.viewTextureView(shadowDepth.view);
		depth.depthClearValue(1);
		depth.depthLoadOp(Clear);
		depth.depthStoreOp(Discard);
		var pass = new GpuRenderPassDescriptor();
		pass.addColorAttachments(color);
		pass.depthStencilAttachment(depth);
		encoder.beginRenderPass(pass);
		var defaults = ensureDefaults(frame);
		var bound:Null<GpuBindGroup> = null;
		for (slot in 0...order.length) {
			var d = draws[order[slot]];
			var m = d.material;
			// Faded meshes let light through: they cast none.
			if (d.opacity < 1 || solid[slot])
				continue;
			var group = shadowGroup;
			if (m.alphaMode != Opaque) {
				var known = cutouts.get(m);
				if (known == null || known.buffers != buffers || known.textures != MeshTextures.revision) {
					if (known != null)
						known.group.destroy();
					var t = m.baseColorTexture != null ? MeshTextures.get(device, m.baseColorTexture, Color) : null;
					var bindings = new GpuBindings();
					bindings.texture(t != null ? t.view : defaults.white.view);
					bindings.sampler(sampler);
					bindings.buffer(sceneBuffer);
					bindings.buffer(drawBuffer);
					known = {group: device.bindGroup(cutoutPipeline, 0, bindings), used: frameCount, buffers: buffers, textures: MeshTextures.revision};
					bindings.destroy();
					cutouts.set(m, known);
				}
				known.used = frameCount;
				group = known.group;
			}
			if (group != bound) {
				encoder.renderSetPipeline(group == shadowGroup ? shadowPipeline : cutoutPipeline);
				encoder.renderSetBindGroup(0, group);
				bound = group;
			}
			var gpu = meshes.get(d.mesh);
			encoder.renderSetVertexBuffer(0, gpu.vertices);
			encoder.renderSetIndexBufferRange(gpu.indices, Uint32, 0, d.mesh.indexCount * 4);
			encoder.renderDrawIndexedRange(d.mesh.indexCount, 1, 0, 0, slot);
		}
		// A pass draws with its own pipeline: it binds what it needs.
		for (p in passes)
			if (Std.isOfType(p, ashui.draw3d.ScenePass.ShadowCaster))
				(cast p : ashui.draw3d.ScenePass.ShadowCaster).drawShadow(passFrame);
		encoder.renderEnd();
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

	static function sceneBytes(scene:Scene3D, viewProjection:Mat4, environment:Null<ashui.draw3d.SceneLighting.EnvironmentMap>,
			shadows:Null<ashui.draw3d.SceneLighting.ShadowSettings>, drawCount:Int):haxe.io.Bytes {
		var out = haxe.io.Bytes.alloc(ashui.shaders.Scene.ROWS * 16);
		viewProjection.write(out, 0);
		var lighting = scene.lighting;
		var lights = lighting.lights().slice(0, ashui.shaders.Scene.MAX_LIGHTS);
		var eye = scene.camera.eye;
		row(out, 4, eye.x, eye.y, eye.z, lights.length);
		var a = lighting.ambientColor(), s = lighting.ambientStrength();
		row(out, 5, linear(a >> 16 & 0xff) * s, linear(a >> 8 & 0xff) * s, linear(a & 0xff) * s, scene.exposure);
		var fog = scene.fog;
		row(out, 6, environment != null ? environment.intensity : 0, environment != null ? environment.levels - 1 : 0, environment != null ? 1 : 0,
			fog != null ? Math.max(fog.far, fog.near + 0.001) : 0);
		if (fog != null)
			row(out, 12, linear(fog.color >> 16 & 0xff), linear(fog.color >> 8 & 0xff), linear(fog.color & 0xff), fog.near);
		row(out, 13, fog != null ? fog.opacity : 0, drawCount, 0, 0);
		if (shadows != null) {
			shadows.viewProjection.write(out, 7 * 16);
			row(out, 11, 1, shadows.bias, shadows.strength, Std.int(Math.max(16, Math.min(8192, shadows.size))));
		}
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

	/** A draw's rows; `solid` for the half of a blended material drawn with the opaque meshes, its alpha mode 3. **/
	static function writeDraw(out:haxe.io.Bytes, offset:Int, d:SceneDraw, solid:Bool):Void {
		d.transform.write(out, offset);
		var n = d.transform.normalMatrix().m;
		var m = d.material;
		var t = m.textureTransform != null ? m.textureTransform : ashui.draw3d.TextureTransform.IDENTITY;
		var offsets = [t.offsetX, t.offsetY, 0];
		for (c in 0...3)
			for (r in 0...4)
				out.setFloat(offset + (4 + c) * 16 + r * 4, r < 3 ? n[c * 4 + r] : offsets[c]);
		var at = Std.int(offset / 16);
		row(out, at + 7, linear(m.baseColor >> 16 & 0xff), linear(m.baseColor >> 8 & 0xff), linear(m.baseColor & 0xff), m.alpha);
		row(out, at + 8, m.metallic, m.roughness, m.normalScale, m.occlusionTexture != null ? m.occlusionStrength : 0);
		var e = m.emissive, k = m.emissiveStrength;
		row(out, at + 9, linear(e >> 16 & 0xff) * k, linear(e >> 8 & 0xff) * k, linear(e & 0xff) * k, m.alphaCutoff);
		// Unlit is 1, or 2 out of the fog; lit meshes are always in it.
		row(out, at + 10, m.normalTexture != null ? 1 : 0, m.unlit ? (m.fog ? 1 : 2) : 0, solid ? 3 : (m.alphaMode : Int), d.opacity);
		var uv = t.matrix();
		row(out, at + 11, uv.a, uv.b, uv.c, uv.d);
	}

	static inline function row(out:haxe.io.Bytes, at:Int, x:Float, y:Float, z:Float, w:Float):Void {
		out.setFloat(at * 16, x);
		out.setFloat(at * 16 + 4, y);
		out.setFloat(at * 16 + 8, z);
		out.setFloat(at * 16 + 12, w);
	}
}
