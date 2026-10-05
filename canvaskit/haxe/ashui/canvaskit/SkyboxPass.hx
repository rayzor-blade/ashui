package ashui.canvaskit;

import ashui.draw3d.ScenePass;

/**
	A `Skybox` drawn behind a scene's meshes, as `<scene-kit skybox={...}>`
	draws it: set `skybox` to what to show. It frees what it put on the
	GPU with `dispose`.
**/
class SkyboxPass implements ScenePass implements GlowCaster {
	public var skybox:Null<Skybox>;

	public function new(?skybox:Skybox)
		this.skybox = skybox;

	public function stage():SceneStage
		return Background;

	public function animated():Bool
		return false;

	#if ashui_gpu
	/** Rows of `SkyShader`'s settings. **/
	static inline var ROWS = 12;

	var pipeline:Null<gpu.GpuPipeline> = null;
	var settings:Null<gpu.GpuBuffer> = null;
	var group:Null<gpu.GpuBindGroup> = null;

	/** For bloom's glow pass: its pipeline, and settings and a bind group flagged for glow. **/
	var glowPipeline:Null<gpu.GpuPipeline> = null;
	var glowSettings:Null<gpu.GpuBuffer> = null;
	var glowGroup:Null<gpu.GpuBindGroup> = null;

	/** Whether what it shows is on the GPU: a panorama waits for its texture. **/
	var ready = false;

	public function prepare(frame:ScenePassFrame):Void {
		if (skybox == null)
			return;
		if (pipeline == null) {
			var builder = frame.pipelineBuilder(SkyShader.WGSL, false, false);
			// At the far plane, where the cleared depth is: drawn wherever nothing is nearer, which is everywhere before the meshes.
			builder.depth(frame.depthFormat, false, Always);
			builder.primitive(TriangleList, None, Ccw);
			pipeline = builder.build();
			settings = frame.device.createBuffer(new gpu.GpuBufferDescriptor(ROWS * 16, ashui.core.render.GpuFlags.BUFFER_STORAGE | ashui.core.render.GpuFlags.BUFFER_COPY_DST));
		}
		var b = haxe.io.Bytes.alloc(ROWS * 16);
		inline function row(at:Int, x:Float, y:Float, z:Float, w:Float) {
			b.setFloat(at * 16, x);
			b.setFloat(at * 16 + 4, y);
			b.setFloat(at * 16 + 8, z);
			b.setFloat(at * 16 + 12, w);
		}
		inline function lin(c:Int, shift:Int):Float {
			var v = (c >> shift & 0xff) / 255;
			return v <= 0.04045 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4);
		}
		var inverse = frame.viewProjection.inverse();
		(inverse != null ? inverse : ashui.math.Mat4.IDENTITY).write(b, 0);
		var eye = frame.scene.camera.eye;
		row(4, eye.x, eye.y, eye.z, 0);
		var cube = frame.environment;
		// A panorama's image, or any 2D texture to fill its binding: the shadow map is always there.
		var flat = frame.shadowMap;
		switch skybox {
			case Panorama(image, o):
				// Kept exact: block compression smears a sky's stars.
				image.compressible = false;
				var t = ashui.core.render.MeshTextures.get(frame.device, image, Color);
				// Drawn once its texture is on the GPU; until then, nothing.
				if (t == null) {
					ready = false;
					return;
				}
				flat = t.view;
				var o = o != null ? o : {};
				row(5, 3, 0, o.intensity != null ? o.intensity : 1, 0);
				// Texels a radian round, for the mip level a pixel's share of the sky asks for.
				row(9, o.spread != null ? o.spread : 1, o.upsideDown == true ? 1 : 0, image.width / (2 * Math.PI), (o.turn != null ? o.turn : 0) / (2 * Math.PI));
				var c = o.centre != null ? o.centre : ashui.math.Vec3.ZERO;
				row(10, c.x, c.y, c.z, o.radius != null ? o.radius : 0);
			case Sky(e, blur, intensity):
				cube = e.upload(frame.device);
				row(5, 1, (blur != null ? blur : 0) * (e.levels - 1), intensity != null ? intensity : 1, 0);
			case Grounded(e, height, radius, floor, blur, intensity):
				cube = e.upload(frame.device);
				row(5, 1, (blur != null ? blur : 0) * (e.levels - 1), intensity != null ? intensity : 1, 1);
				row(9, floor != null ? floor : 0, height, radius, 0);
			case Gradient(zenith, horizon, ground):
				row(5, 2, 0, 1, 0);
				row(6, lin(zenith, 16), lin(zenith, 8), lin(zenith, 0), 0);
				row(7, lin(horizon, 16), lin(horizon, 8), lin(horizon, 0), 0);
				row(8, lin(ground, 16), lin(ground, 8), lin(ground, 0), 0);
		}
		frame.device.queue().writeBuffer(settings, 0, b, b.length);
		if (group != null)
			group.destroy();
		var bindings = new gpu.GpuBindings();
		bindings.texture(cube);
		bindings.sampler(frame.environmentSampler);
		bindings.texture(frame.shadowMap);
		bindings.sampler(frame.shadowSampler);
		bindings.texture(flat);
		bindings.sampler(frame.environmentSampler);
		bindings.buffer(frame.sceneBuffer);
		bindings.buffer(settings);
		group = frame.device.bindGroup(pipeline, 0, bindings);
		// The glow pass reads the same settings with the glow flag set, through its own pipeline.
		if (glowPipeline == null) {
			var builder = frame.glowPipelineBuilder(SkyShader.WGSL);
			glowPipeline = builder.build();
			glowSettings = frame.device.createBuffer(new gpu.GpuBufferDescriptor(ROWS * 16, ashui.core.render.GpuFlags.BUFFER_STORAGE | ashui.core.render.GpuFlags.BUFFER_COPY_DST));
		}
		row(11, 1, 0, 0, 0);
		frame.device.queue().writeBuffer(glowSettings, 0, b, b.length);
		if (glowGroup != null)
			glowGroup.destroy();
		var glowBindings = new gpu.GpuBindings();
		glowBindings.texture(cube);
		glowBindings.sampler(frame.environmentSampler);
		glowBindings.texture(frame.shadowMap);
		glowBindings.sampler(frame.shadowSampler);
		glowBindings.texture(flat);
		glowBindings.sampler(frame.environmentSampler);
		glowBindings.buffer(frame.sceneBuffer);
		glowBindings.buffer(glowSettings);
		glowGroup = frame.device.bindGroup(glowPipeline, 0, glowBindings);
		glowBindings.destroy();
		bindings.destroy();
		ready = true;
	}

	public function draw(frame:ScenePassFrame):Void {
		if (skybox == null || !ready)
			return;
		frame.encoder.renderSetPipeline(pipeline);
		frame.encoder.renderSetBindGroup(0, group);
		frame.encoder.renderDraw(3, 1);
	}

	/** Draws the sky's light, without tone mapping, for bloom. **/
	public function drawGlow(frame:ScenePassFrame):Void {
		if (skybox == null || !ready || glowGroup == null)
			return;
		frame.encoder.renderSetPipeline(glowPipeline);
		frame.encoder.renderSetBindGroup(0, glowGroup);
		frame.encoder.renderDraw(3, 1);
	}

	/** Frees what it put on the GPU; drawn again, it makes it again. **/
	public function dispose():Void {
		if (group != null)
			group.destroy();
		if (settings != null)
			settings.destroy();
		if (glowGroup != null)
			glowGroup.destroy();
		if (glowSettings != null)
			glowSettings.destroy();
		group = null;
		settings = null;
		glowGroup = null;
		glowSettings = null;
		pipeline = null;
		glowPipeline = null;
	}
	#else
	public function prepare(frame:ScenePassFrame):Void {}

	public function draw(frame:ScenePassFrame):Void {}

	public function drawGlow(frame:ScenePassFrame):Void {}

	public function dispose():Void {}
	#end
}
