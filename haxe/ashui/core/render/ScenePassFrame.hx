package ashui.core.render;

import ashui.draw3d.Scene3D;
import ashui.math.Mat4;
import gpu.GpuBuffer;
import gpu.GpuDevice;
import gpu.GpuEncoder;
import gpu.GpuPipelineBuilder;
import gpu.GpuSampler;
import gpu.GpuTextureView;
import gpu.TextureFormat;

/**
	What a `ScenePass` draws with: the scene's layer, its camera and its
	lighting, for one render of the scene.

	`encoder` is free in `prepare` and inside the scene's render pass in
	`draw`. `sceneBuffer` is the scene's storage buffer as
	`ashui.shaders.Scene` reads it (camera, lights, ambient light,
	exposure, environment), `environment` the lighting's cubemap, a black
	one when it has none; the lighting prepares before the passes do. Each is good only during the call it is handed to.
**/
@:allow(ashui.core.render.ScenePainter)
class ScenePassFrame {
	public final device:GpuDevice;
	public final encoder:GpuEncoder;

	/** The layer's colour format, premultiplied alpha, sRGB-encoded values. **/
	public final format:TextureFormat;

	public final depthFormat:TextureFormat;

	/** The layer's size in pixels. **/
	public final width:Int;

	public final height:Int;

	public final scene:Scene3D;
	public final view:Mat4;
	public final projection:Mat4;
	public final viewProjection:Mat4;
	public final sceneBuffer:GpuBuffer;

	/** The lighting's environment cubemap once it has prepared, a black one before and where it has none. **/
	public var environment(default, null):GpuTextureView;

	public final environmentSampler:GpuSampler;

	/** The animation scheduler's clock, in seconds. **/
	public final time:Float;

	@:allow(ashui.core.render.ScenePainter)
	function new(device:GpuDevice, encoder:GpuEncoder, format:TextureFormat, depthFormat:TextureFormat, width:Int, height:Int, scene:Scene3D,
			view:Mat4, projection:Mat4, sceneBuffer:GpuBuffer, environment:GpuTextureView, environmentSampler:GpuSampler) {
		this.device = device;
		this.encoder = encoder;
		this.format = format;
		this.depthFormat = depthFormat;
		this.width = width;
		this.height = height;
		this.scene = scene;
		this.view = view;
		this.projection = projection;
		this.viewProjection = projection.mul(view);
		this.sceneBuffer = sceneBuffer;
		this.environment = environment;
		this.environmentSampler = environmentSampler;
		this.time = ashui.animation.AnimationScheduler.main.clock;
	}

	/**
		A pipeline builder for a shader of WGSL `wgsl` that draws into the
		layer: its colour target, alpha-blended into premultiplied colour
		unless `blend` is false, and its depth, tested and written unless
		`depthWrite` is false; triangles, back faces culled. Add vertex
		buffers and attributes, call `primitive` to cull otherwise, then
		`build`; keep what it builds, as building is slow.
	**/
	public function pipelineBuilder(wgsl:String, blend = true, depthWrite = true):GpuPipelineBuilder {
		var builder = device.pipeline();
		builder.shader(device.createShader(wgsl), "vertex", "fragment");
		builder.target(format, GpuFlags.COLOR_WRITE_ALL);
		if (blend)
			builder.blend(SrcAlpha, OneMinusSrcAlpha, Add, One, OneMinusSrcAlpha, Add);
		builder.depth(depthFormat, depthWrite, Less);
		builder.primitive(TriangleList, Back, Ccw);
		return builder;
	}
}
