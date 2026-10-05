package ashui.canvaskit;

import ashui.draw3d.ScenePass;

/** A ground grid's settings, each optional; see `GroundGrid`. **/
typedef GroundGridOptions = {
	?size:Float,
	?subdivisions:Int,
	?minor:Int,
	?minorAlpha:Float,
	?major:Int,
	?majorAlpha:Float,
	?axes:Bool,
	?fadeNear:Float,
	?fadeFar:Float,
	?height:Float,
}

/**
	A ground grid under a 3D scene, as modelling tools draw one: a line each
	`size` units (major) and `subdivisions` between (minor), the X axis red
	and the Z axis blue where `axes` is set, fading out from `fadeNear` to
	`fadeFar` units from the camera. It lies flat at `height`, and meshes
	hide it where they are in front, so a model stands on it. Colours are
	`0xRRGGBB`, as `Brush` takes them. (Named apart from CSS's `display:
	grid`, `Display.Grid`, which a page usually has imported.)

	```haxe
	grid={GroundGrid.studio()}
	grid={new GroundGrid({size: 0.5, height: helmet.min.y})}
	```

	It is a `ScenePass`: `<scene-kit grid={...}>` draws it, and a canvas
	can with `ctx.drawPass(grid)`. It frees what it put on the GPU with
	`dispose`.
**/
class GroundGrid implements ScenePass {
	public final size:Float;
	public final subdivisions:Int;
	public final minor:Int;
	public final minorAlpha:Float;
	public final major:Int;
	public final majorAlpha:Float;
	public final axes:Bool;
	public final fadeNear:Float;
	public final fadeFar:Float;
	public final height:Float;

	public function new(?o:GroundGridOptions) {
		if (o == null)
			o = {};
		size = o.size != null ? o.size : 1;
		subdivisions = o.subdivisions != null ? o.subdivisions : 10;
		minor = o.minor != null ? o.minor : 0x808080;
		minorAlpha = o.minorAlpha != null ? o.minorAlpha : 0.25;
		major = o.major != null ? o.major : 0xa0a0a0;
		majorAlpha = o.majorAlpha != null ? o.majorAlpha : 0.55;
		axes = o.axes != false;
		fadeNear = o.fadeNear != null ? o.fadeNear : 4;
		fadeFar = o.fadeFar != null ? o.fadeFar : 20;
		height = o.height != null ? o.height : 0;
	}

	/** A studio floor: a line a unit, tenths between, axes coloured, fading out by twenty units; at `height`. **/
	public static function studio(height = 0.0):GroundGrid
		return new GroundGrid({height: height});

	public function stage():SceneStage
		return Transparent;

	public function animated():Bool
		return false;

	#if ashui_gpu
	var pipeline:Null<gpu.GpuPipeline> = null;
	var settings:Null<gpu.GpuBuffer> = null;
	var group:Null<gpu.GpuBindGroup> = null;
	var groupScene = -1;

	public function prepare(frame:ScenePassFrame):Void {
		if (pipeline == null) {
			var builder = frame.pipelineBuilder(GridShader.WGSL, true, false);
			builder.primitive(TriangleList, None, Ccw);
			pipeline = builder.build();
			settings = frame.device.createBuffer(new gpu.GpuBufferDescriptor(64, ashui.core.render.GpuFlags.BUFFER_STORAGE | ashui.core.render.GpuFlags.BUFFER_COPY_DST));
		}
		var b = haxe.io.Bytes.alloc(64);
		inline function row(at:Int, x:Float, y:Float, z:Float, w:Float) {
			b.setFloat(at * 16, x);
			b.setFloat(at * 16 + 4, y);
			b.setFloat(at * 16 + 8, z);
			b.setFloat(at * 16 + 12, w);
		}
		row(0, size, Math.max(1, subdivisions), fadeNear, fadeFar);
		row(1, (minor >> 16 & 0xff) / 255, (minor >> 8 & 0xff) / 255, (minor & 0xff) / 255, minorAlpha);
		row(2, (major >> 16 & 0xff) / 255, (major >> 8 & 0xff) / 255, (major & 0xff) / 255, majorAlpha);
		row(3, height, axes ? 1 : 0, 0, 0);
		frame.device.queue().writeBuffer(settings, 0, b, 64);
		// The scene's buffer is made again as scenes grow: the group follows it.
		if (group == null || groupScene != (frame.sceneBuffer : Int)) {
			if (group != null)
				group.destroy();
			var bindings = new gpu.GpuBindings();
			bindings.buffer(frame.sceneBuffer);
			bindings.buffer(settings);
			group = frame.device.bindGroup(pipeline, 0, bindings);
			bindings.destroy();
			groupScene = (frame.sceneBuffer : Int);
		}
	}

	public function draw(frame:ScenePassFrame):Void {
		frame.encoder.renderSetPipeline(pipeline);
		frame.encoder.renderSetBindGroup(0, group);
		frame.encoder.renderDraw(6, 1);
	}

	/** Frees what it put on the GPU; drawn again, it makes it again. **/
	public function dispose():Void {
		if (group != null)
			group.destroy();
		if (settings != null)
			settings.destroy();
		group = null;
		settings = null;
		pipeline = null;
		groupScene = -1;
	}
	#else
	public function prepare(frame:ScenePassFrame):Void {}

	public function draw(frame:ScenePassFrame):Void {}

	public function dispose():Void {}
	#end
}
