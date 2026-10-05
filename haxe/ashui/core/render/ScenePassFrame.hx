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

	/** The box round the scene's meshes as placed, where a lighting fits its shadows. **/
	public final bounds:{min:ashui.math.Vec3, max:ashui.math.Vec3};

	/** The scene's shadow map, depth from the light in its red, sampled with `shadowSampler`; one holding "far" where there are no shadows. **/
	public var shadowMap(default, null):GpuTextureView;

	public var shadowSampler(default, null):GpuSampler;

	/** The shadow map's colour format, and the shadow pass's depth format. **/
	public static inline var SHADOW_FORMAT = TextureFormat.R16float;

	/** The format of the glow target that bloom's glow pass draws into. **/
	public static inline var GLOW_FORMAT = TextureFormat.Rgba16float;

	/** The format of the velocity target the glow pass also draws, for motion blur. **/
	public static inline var VELOCITY_FORMAT = TextureFormat.Rgba16float;

	public static inline var SHADOW_DEPTH_FORMAT = TextureFormat.Depth24plus;

	@:allow(ashui.core.render.ScenePainter)
	function new(device:GpuDevice, encoder:GpuEncoder, format:TextureFormat, depthFormat:TextureFormat, width:Int, height:Int, scene:Scene3D,
			view:Mat4, projection:Mat4, sceneBuffer:GpuBuffer, environment:GpuTextureView, environmentSampler:GpuSampler,
			bounds:{min:ashui.math.Vec3, max:ashui.math.Vec3}, shadowMap:GpuTextureView, shadowSampler:GpuSampler) {
		this.bounds = bounds;
		this.shadowMap = shadowMap;
		this.shadowSampler = shadowSampler;
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

	/**
		A pipeline builder for a `GlowCaster`'s glow pass: it draws into the
		half-float glow target at half the layer's size, unblended, and tests
		against the depth the glow pass's meshes left there with LessEqual,
		without writing it, so only what is visible glows.
		The pass also has a velocity target for motion blur, which this
		builder leaves unwritten, so a pass's own drawing is not blurred.
		Triangles are not culled. Add vertex buffers and attributes, then
		`build`.
	**/
	public function glowPipelineBuilder(wgsl:String):GpuPipelineBuilder {
		var builder = device.pipeline();
		builder.shader(device.createShader(wgsl), "vertex", "fragment");
		builder.target(GLOW_FORMAT, GpuFlags.COLOR_WRITE_ALL);
		builder.target(VELOCITY_FORMAT, 0);
		builder.depth(depthFormat, false, LessEqual);
		builder.primitive(TriangleList, None, Ccw);
		return builder;
	}

	/**
		A pipeline builder for a `ShadowCaster`'s shader: into the shadow map,
		depth tested and written, unblended, triangles unculled. Its fragment
		writes its light-space depth as `ashui.shaders.Shadows.shadowDepth`
		gives it; add vertex buffers and attributes, then `build`.
	**/
	public function shadowPipelineBuilder(wgsl:String):GpuPipelineBuilder {
		var builder = device.pipeline();
		builder.shader(device.createShader(wgsl), "vertex", "fragment");
		builder.target(SHADOW_FORMAT, GpuFlags.COLOR_WRITE_ALL);
		builder.depth(SHADOW_DEPTH_FORMAT, true, Less);
		builder.primitive(TriangleList, None, Ccw);
		return builder;
	}
}
