package ashui.render;

import ashui.layout.DisplayList;
import gpu.BlendFactor;
import gpu.BlendOperation;
import gpu.BufferUsage;
import gpu.ColorWrite;
import gpu.CullMode;
import gpu.FrontFace;
import gpu.GpuBindGroup;
import gpu.GpuBindings;
import gpu.GpuBuffer;
import gpu.GpuBufferDescriptor;
import gpu.GpuDevice;
import gpu.GpuEncoder;
import gpu.GpuPipeline;
import gpu.GpuTextureView;
import gpu.PrimitiveTopology;
import gpu.TextureFormat;
import gpu.VertexFormat;
import gpu.VertexStepMode;

/**
	Draws a `DisplayList` with the GPU, the way Blinc's renderer draws its
	primitives: each record is an instanced quad of six vertices, and each
	run of records of one kind is one draw with that kind's pipeline, so
	paint order holds across kinds. Colours are straight alpha, blended over
	the target in gamma space as Blinc does on native targets.

	Written against hlwgpu's `gpu` package; the shaders are HXSL, so
	caribou-gpu takes the same ones.
**/
class Renderer {
	final device:GpuDevice;
	final frame:GpuBuffer;
	final frameBytes:haxe.io.Bytes;
	final boxes:Pass;
	final shadows:Pass;
	var instances:Null<GpuBuffer> = null;
	var instanceCapacity = 0;

	/** A renderer drawing into targets of `format`; pick a non-sRGB one, as Blinc does. **/
	public function new(device:GpuDevice, format:TextureFormat) {
		this.device = device;
		frameBytes = haxe.io.Bytes.alloc(BoxShader.FRAME_SIZE);
		frame = device.createBuffer(new GpuBufferDescriptor(BoxShader.FRAME_SIZE, BufferUsage.UNIFORM | BufferUsage.COPY_DST));
		boxes = pass(BoxShader.WGSL, Inputs.of(ashui.render.BoxShader), format);
		shadows = pass(ShadowShader.WGSL, Inputs.of(ashui.render.ShadowShader), format);
	}

	function pass(wgsl:String, inputs:Array<{offset:Int, location:Int}>, format:TextureFormat):Pass {
		var shader = device.createShader(wgsl);
		var builder = device.pipeline();
		builder.shader(shader, "vertex", "fragment");
		builder.vertexBuffer(DisplayList.RECORD_BYTES, VertexStepMode.Instance);
		for (input in inputs)
			builder.attribute(VertexFormat.Float32x4, input.offset, input.location);
		builder.target(format, ColorWrite.ALL);
		builder.blend(BlendFactor.SrcAlpha, BlendFactor.OneMinusSrcAlpha, BlendOperation.Add, BlendFactor.One, BlendFactor.OneMinusSrcAlpha,
			BlendOperation.Add);
		builder.primitive(PrimitiveTopology.TriangleList, CullMode.None, FrontFace.Ccw);
		var pipeline = builder.build();
		failOnError('building a pipeline: ${shader.messages()}');
		// An inferred layout is the pipeline's own, so each pipeline gets its own group.
		var bindings = new GpuBindings();
		bindings.buffer(frame);
		var group = device.bindGroup(pipeline, BoxShader.FRAME_GROUP, bindings);
		bindings.destroy();
		return {pipeline: pipeline, group: group};
	}

	/** Draws `list` into `view`, `width` × `height` pixels, after clearing it to the given colour. **/
	public function draw(list:DisplayList, view:GpuTextureView, width:Int, height:Int, r = 0.0, g = 0.0, b = 0.0, a = 0.0):Void {
		var queue = device.queue();
		frameBytes.setFloat(BoxShader.FRAME_viewport, width);
		frameBytes.setFloat(BoxShader.FRAME_viewport + 4, height);
		queue.writeBuffer(frame, 0, frameBytes, frameBytes.length);
		if (list.count > 0) {
			reserve(list.count);
			queue.writeBuffer(instances, 0, list.bytes, list.count * DisplayList.RECORD_BYTES);
		}
		var encoder = device.encoder();
		encoder.passColour(view, r, g, b, a);
		encoder.passBegin();
		if (list.count > 0) {
			encoder.renderSetVertexBuffer(0, instances);
			var start = 0;
			while (start < list.count) {
				var kind = list.kind(start);
				var end = start + 1;
				while (end < list.count && list.kind(end) == kind)
					end++;
				drawRun(encoder, kind == DisplayList.PRIM_SHADOW ? shadows : boxes, start, end - start);
				start = end;
			}
		}
		encoder.renderEnd();
		encoder.submit(queue);
		failOnError("drawing");
	}

	function drawRun(encoder:GpuEncoder, pass:Pass, first:Int, count:Int):Void {
		encoder.renderSetPipeline(pass.pipeline);
		encoder.renderSetBindGroup(BoxShader.FRAME_GROUP, pass.group);
		encoder.renderDrawRange(6, count, 0, first);
	}

	/** Grows the instance buffer to hold `records`. **/
	function reserve(records:Int):Void {
		if (records <= instanceCapacity)
			return;
		if (instances != null)
			instances.destroy();
		instanceCapacity = records + (records >> 1) + 16;
		instances = device.createBuffer(new GpuBufferDescriptor(instanceCapacity * DisplayList.RECORD_BYTES, BufferUsage.VERTEX | BufferUsage.COPY_DST));
	}

	/** wgpu reports validation errors on the device, not by throwing. **/
	function failOnError(doing:String):Void {
		var error = device.takeError();
		if (error != null)
			throw 'gpu error $doing: $error';
	}
}

private typedef Pass = {
	final pipeline:GpuPipeline;
	final group:GpuBindGroup;
}
