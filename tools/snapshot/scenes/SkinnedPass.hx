import ashui.canvaskit.Geometry;
import ashui.canvaskit.GroundGrid;
import ashui.canvaskit.OrbitCamera;
import ashui.canvaskit.SceneKit;
import ashui.core.render.GpuFlags;
import ashui.core.render.ScenePassFrame;
import ashui.core.render.Snapshot;
import ashui.draw3d.Light;
import ashui.draw3d.Material;
import ashui.draw3d.ScenePass;
import ashui.math.Mat4;
import ashui.math.Quat;
import ashui.math.Vec3;
import ashui.theme.ThemeState;
import ashui.theme.themes.DefaultTheme;
import ashui.types.Style;
import haxe.io.Bytes;

/**
	One's own GPU drawing in a 3D scene, as a game's renderer would add it:
	a tube skinned to two bones and bent at its middle, drawn by a
	`ScenePass` with its own vertex layout, bone buffer, shader and
	pipeline, lit through ashui's `Scene`, `Pbr` and `ColorSpace` shader
	modules as ashui's own meshes are. It stands on a box ashui draws and
	on a ground grid, all sharing one depth buffer. Writes
	`.ashui/snapshots/skinned-pass.png`.
**/
class SkinnedPass {
	static function main() {
		ThemeState.init(DefaultTheme.bundle(), Dark);
		var page = ThemeState.get().color(Background);
		var tube = new SkinnedTube(0.9);
		var pedestal = Geometry.box(1.2, 0.3, 1.2, new Material({baseColor: 0x505866, roughness: 0.6}));
		var camera = new OrbitCamera(0.5, 0.35, 5.5, new Vec3(0, 1.1, 0), 0.7);
		var rig = [Directional(new Vec3(-0.5, -1, -0.4), 0xffffff, 2.5), Directional(new Vec3(0.7, -0.2, 0.6), 0x88aaff, 0.6)];
		function draw(ctx:ashui.draw.DrawContext) {
			ctx.drawMesh(pedestal, Mat4.translation(new Vec3(0, 0.15, 0)));
			ctx.drawPass(tube);
		}
		var build = () -> <div padding={20}><scene-kit camera={camera} lights={rig} ambientStrength={0.4} grid={GroundGrid.studio()} draw={draw} width={600} height={480} /></div>;
		Snapshot.scene("skinned-pass", 640, 520, build, page.rgb(), page.a, 2.0, 1.0);
	}
}

/**
	A tube two units tall standing on the pedestal, its vertices weighted
	from the lower bone to the upper one across its middle; the upper bone
	turned by `bend` radians about the middle. Each vertex is its position,
	normal and weight on the upper bone, 32 bytes.
**/
class SkinnedTube implements ScenePass {
	static inline var STRIDE = 32;

	final bend:Float;
	var vertices:Null<gpu.GpuBuffer> = null;
	var indices:Null<gpu.GpuBuffer> = null;
	var indexCount = 0;
	var bones:Null<gpu.GpuBuffer> = null;
	var pipeline:Null<gpu.GpuPipeline> = null;
	var group:Null<gpu.GpuBindGroup> = null;

	public function new(bend:Float)
		this.bend = bend;

	public function stage():SceneStage
		return Opaque;

	public function animated():Bool
		return false;

	public function prepare(frame:ScenePassFrame):Void {
		if (pipeline == null) {
			upload(frame);
			var builder = frame.pipelineBuilder(SkinnedTubeShader.WGSL);
			builder.vertexBuffer(STRIDE, Vertex);
			builder.attribute(Float32x3, 0, SkinnedTubeShader.INPUT_position);
			builder.attribute(Float32x3, 12, SkinnedTubeShader.INPUT_normal);
			builder.attribute(Float32, 24, SkinnedTubeShader.INPUT_weight);
			pipeline = builder.build();
			bones = frame.device.createBuffer(new gpu.GpuBufferDescriptor(128, GpuFlags.BUFFER_STORAGE | GpuFlags.BUFFER_COPY_DST));
		}
		// The bones: the lower where the tube stands, the upper turned about the tube's middle.
		var base = Mat4.translation(new Vec3(0, 0.3, 0));
		var middle = new Vec3(0, 1, 0);
		var upper = base.mul(Mat4.translation(middle)).mul(Mat4.rotation(Quat.axisAngle(new Vec3(0, 0, 1), bend))).mul(Mat4.translation(middle.negate()));
		var b = Bytes.alloc(128);
		base.write(b, 0);
		upper.write(b, 64);
		frame.device.queue().writeBuffer(bones, 0, b, 128);
		if (group != null)
			group.destroy();
		var bindings = new gpu.GpuBindings();
		bindings.buffer(frame.sceneBuffer);
		bindings.buffer(bones);
		group = frame.device.bindGroup(pipeline, 0, bindings);
		bindings.destroy();
	}

	public function draw(frame:ScenePassFrame):Void {
		frame.encoder.renderSetPipeline(pipeline);
		frame.encoder.renderSetBindGroup(0, group);
		frame.encoder.renderSetVertexBuffer(0, vertices);
		frame.encoder.renderSetIndexBufferRange(indices, Uint32, 0, indexCount * 4);
		frame.encoder.renderDrawIndexedRange(indexCount, 1, 0, 0, 0);
	}

	function upload(frame:ScenePassFrame):Void {
		var rings = 32, segments = 32, radius = 0.22, height = 2.0;
		var v = Bytes.alloc((rings + 1) * (segments + 1) * STRIDE);
		var o = 0;
		for (r in 0...rings + 1) {
			var y = r / rings * height;
			// Wholly the lower bone's below 0.7, the upper's above 1.3, blended between.
			var t = Math.max(0, Math.min(1, (y - 0.7) / 0.6));
			var weight = t * t * (3 - 2 * t);
			for (s in 0...segments + 1) {
				var a = s / segments * Math.PI * 2;
				for (f in [Math.sin(a) * radius, y, Math.cos(a) * radius, Math.sin(a), 0.0, Math.cos(a), weight, 0.0]) {
					v.setFloat(o, f);
					o += 4;
				}
			}
		}
		var idx = [];
		for (r in 0...rings)
			for (s in 0...segments) {
				var a = r * (segments + 1) + s, b = a + segments + 1;
				for (i in [a, a + 1, b, b, a + 1, b + 1])
					idx.push(i);
			}
		indexCount = idx.length;
		var ib = Bytes.alloc(idx.length * 4);
		for (i in 0...idx.length)
			ib.setInt32(i * 4, idx[i]);
		vertices = frame.device.createBuffer(new gpu.GpuBufferDescriptor(v.length, GpuFlags.BUFFER_VERTEX | GpuFlags.BUFFER_COPY_DST));
		indices = frame.device.createBuffer(new gpu.GpuBufferDescriptor(ib.length, GpuFlags.BUFFER_INDEX | GpuFlags.BUFFER_COPY_DST));
		frame.device.queue().writeBuffer(vertices, 0, v, v.length);
		frame.device.queue().writeBuffer(indices, 0, ib, ib.length);
	}
}

/** The tube, each vertex placed by the two bones as its weight blends them, lit by the scene's lights as ashui's meshes are. **/
class SkinnedTubeShader implements hlwgpu.hxsl.Shader {
	static var SRC = {
		@:import ashui.shaders.Scene;
		@:import ashui.shaders.Pbr;
		@:import ashui.shaders.ColorSpace;

		@input var input : { position : Vec3, normal : Vec3, weight : Float };
		var output : { position : Vec4, color : Vec4 };

		@param var scene : StorageBuffer<Vec4>;
		@param var bones : StorageBuffer<Vec4>;

		var worldPos : Vec3;
		var worldNormal : Vec3;

		function bone(at : Int, p : Vec4) : Vec4 {
			return bones[at] * p.x + bones[at + 1] * p.y + bones[at + 2] * p.z + bones[at + 3] * p.w;
		}

		function vertex() {
			var p = vec4(input.position, 1.);
			var n = vec4(input.normal, 0.);
			var w = mix(bone(0, p), bone(4, p), input.weight);
			worldPos = w.xyz;
			worldNormal = mix(bone(0, n), bone(4, n), input.weight).xyz;
			output.position = worldToClip(w);
		}

		function fragment() {
			var albedo = vec3(0.9, 0.45, 0.12);
			var n = normalize(worldNormal);
			var v = normalize(cameraEye() - worldPos);
			var lit = vec3(0., 0., 0.);
			var i = 0;
			while (i < 8) {
				if (i < lightCount())
					lit += directLight(n, v, lightDirection(i, worldPos), lightRadiance(i, worldPos), albedo, 0., 0.35);
				i++;
			}
			lit += ambientLight() * albedo;
			output.color = vec4(linearToSrgb(toneMapAces(lit * sceneExposure())), 1.);
		}
	};
}
