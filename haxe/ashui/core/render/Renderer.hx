package ashui.core.render;

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
import gpu.GpuColor;
import gpu.GpuRenderPassColorAttachment;
import gpu.GpuRenderPassDescriptor;
import gpu.LoadOp;
import gpu.StoreOp;
import gpu.GpuExtent3D;
import gpu.GpuTexture;
import gpu.GpuTextureDescriptor;
import gpu.GpuTextureViewDescriptor;
import gpu.TextureUsage;
import gpu.GpuDevice;
import gpu.GpuEncoder;
import gpu.GpuPipeline;
import gpu.GpuSampler;
import gpu.GpuSamplerDescriptor;
import gpu.GpuTextureView;
import gpu.PrimitiveTopology;
import gpu.TextureFormat;

/**
	Draws a `DisplayList` with the GPU, the way Blinc's renderer draws its
	primitives: each record is an instanced quad of six vertices, and each
	run of records of one kind is one draw with that kind's pipeline, so
	paint order holds across kinds. The records are uploaded as rows of a
	float texture each shader reads its instance's record from (see
	`UiFramework`), on every platform alike. A group with opacity draws
	into a layer, a texture the target's size, and is composited back over
	its bounds by `LayerShader`, as CSS composites one. Colours are straight alpha, blended over
	the target in gamma space as Blinc does on native targets. Glyphs sample
	the text engine's atlases, uploaded before each frame that changed them;
	images sample an atlas of their own, rasterized into as they appear.

	Written against hlwgpu's `gpu` package; the shaders are HXSL, so
	caribou-gpu takes the same ones.
**/
class Renderer {
	final device:GpuDevice;
	final frame:GpuBuffer;
	final frameBytes:haxe.io.Bytes;
	final boxes:Pass;
	final shadows:Pass;
	final text:Pass;
	final atlas:GlyphAtlas;
	final colorAtlas:GlyphAtlas;
	final glyphSampler:GpuSampler;
	final images:Pass;
	final imageAtlas:ImageAtlas;
	final layerPass:Pass;
	final format:TextureFormat;
	/** Layer textures by depth, from 1, the target's size, each with its bind group for `layerPass`. **/
	final layers:Array<Layer> = [];
	var imageRevision = -1;
	/** The atlas revisions `text`'s bind group holds views of. **/
	var textRevisions = "";
	var records:Null<GpuTexture> = null;
	/** Rows of the records texture, `DisplayList.RECORDS_PER_ROW` records each. **/
	var recordRows = 0;
	final passes:Array<Pass> = [];

	/** A renderer drawing into targets of `format`; pick a non-sRGB one, as Blinc does. **/
	public function new(device:GpuDevice, format:TextureFormat) {
		this.device = device;
		frameBytes = haxe.io.Bytes.alloc(BoxShader.FRAME_SIZE);
		frame = device.createBuffer(new GpuBufferDescriptor(BoxShader.FRAME_SIZE, BufferUsage.UNIFORM | BufferUsage.COPY_DST));
		boxes = pass(BoxShader.WGSL, format);
		shadows = pass(ShadowShader.WGSL, format);
		atlas = new GlyphAtlas(device, false);
		colorAtlas = new GlyphAtlas(device, true);
		var sampler = new GpuSamplerDescriptor();
		sampler.magFilter(Linear);
		sampler.minFilter(Linear);
		glyphSampler = device.sampler(sampler);
		text = pass(TextShader.WGSL, format, false);
		imageAtlas = new ImageAtlas(device);
		images = pass(ImageShader.WGSL, format, false);
		layerPass = pass(LayerShader.WGSL, format, false);
		this.format = format;
	}

	function pass(wgsl:String, format:TextureFormat, bind = true):Pass {
		var shader = device.createShader(wgsl);
		var builder = device.pipeline();
		builder.shader(shader, "vertex", "fragment");
		builder.target(format, ColorWrite.ALL);
		builder.blend(BlendFactor.SrcAlpha, BlendFactor.OneMinusSrcAlpha, BlendOperation.Add, BlendFactor.One, BlendFactor.OneMinusSrcAlpha,
			BlendOperation.Add);
		builder.primitive(PrimitiveTopology.TriangleList, CullMode.None, FrontFace.Ccw);
		var pipeline = builder.build();
		failOnError('building a pipeline: ${shader.messages()}');
		// An inferred layout is the pipeline's own, so each pipeline gets its own group.
		var group:Null<GpuBindGroup> = null;
		if (bind) {
			var bindings = new GpuBindings();
			bindings.buffer(frame);
			group = device.bindGroup(pipeline, BoxShader.FRAME_GROUP, bindings);
			bindings.destroy();
		}
		var made:Pass = {pipeline: pipeline, group: group, records: null};
		passes.push(made);
		return made;
	}

	/** Uploads changed atlases, and binds the text pass to their current views. **/
	function syncText():Void {
		atlas.sync();
		colorAtlas.sync();
		var revisions = '${atlas.revision}/${colorAtlas.revision}';
		if (revisions == textRevisions)
			return;
		// Bindings follow the shader's order: the frame block, then each texture and its sampler.
		var bindings = new GpuBindings();
		bindings.buffer(frame);
		bindings.texture(atlas.view);
		bindings.sampler(glyphSampler);
		bindings.texture(colorAtlas.view);
		bindings.sampler(glyphSampler);
		if (text.group != null)
			text.group.destroy();
		text.group = device.bindGroup(text.pipeline, TextShader.FRAME_GROUP, bindings);
		bindings.destroy();
		textRevisions = revisions;
	}

	/** Rasterizes the list's new images, and binds the image pass to the atlas's current view. **/
	function syncImages(list:DisplayList):Void {
		Images.resolve(list, imageAtlas);
		if (imageAtlas.revision == imageRevision)
			return;
		var bindings = new GpuBindings();
		bindings.buffer(frame);
		bindings.texture(imageAtlas.view);
		bindings.sampler(glyphSampler);
		if (images.group != null)
			images.group.destroy();
		images.group = device.bindGroup(images.pipeline, ImageShader.FRAME_GROUP, bindings);
		bindings.destroy();
		imageRevision = imageAtlas.revision;
	}

	/** Draws `list` into `view`, `width` × `height` pixels, after clearing it to the given colour. **/
	public function draw(list:DisplayList, view:GpuTextureView, width:Int, height:Int, r = 0.0, g = 0.0, b = 0.0, a = 0.0):Void {
		var queue = device.queue();
		frameBytes.setFloat(BoxShader.FRAME_viewport, width);
		frameBytes.setFloat(BoxShader.FRAME_viewport + 4, height);
		queue.writeBuffer(frame, 0, frameBytes, frameBytes.length);
		syncText();
		syncImages(list);
		if (list.count > 0) {
			// Whole rows: the list's bytes hold whole rows of records, so the last is complete.
			var rows = Math.ceil(list.stored / DisplayList.RECORDS_PER_ROW);
			reserve(rows);
			queue.writeTexture(records, list.bytes, DisplayList.ROW_TEXELS, rows, DisplayList.ROW_TEXELS * 16);
		}
		var encoder = device.encoder();
		beginPass(encoder, view, true, r, g, b, a);
		if (list.count > 0) {
			var start = 0;
			var depth = 0;
			while (start < list.count) {
				var kind = list.kind(start);
				if (kind == DisplayList.PRIM_LAYER_BEGIN) {
					// What follows draws into a cleared layer, until its composite record.
					encoder.renderEnd();
					depth++;
					beginPass(encoder, layerAt(depth, width, height).view, true, 0, 0, 0, 0);
					start++;
					continue;
				}
				if (kind == DisplayList.PRIM_LAYER) {
					// Back to the layer or target under it, keeping what it holds, to composite this one.
					encoder.renderEnd();
					var inner = layers[depth - 1];
					depth--;
					beginPass(encoder, depth == 0 ? view : layers[depth - 1].view, false, 0, 0, 0, 0);
					encoder.renderSetPipeline(layerPass.pipeline);
					encoder.renderSetBindGroup(LayerShader.FRAME_GROUP, inner.group);
					encoder.renderSetBindGroup(LayerShader.TEXTURE_records_GROUP, layerPass.records);
					encoder.renderDrawRange(6, 1, 0, start);
					start++;
					continue;
				}
				var end = start + 1;
				while (end < list.count && list.kind(end) == kind)
					end++;
				drawRun(encoder, switch kind {
					case DisplayList.PRIM_SHADOW: shadows;
					case DisplayList.PRIM_TEXT: text;
					case DisplayList.PRIM_IMAGE: images;
					default: boxes;
				}, start, end - start);
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
		encoder.renderSetBindGroup(BoxShader.TEXTURE_records_GROUP, pass.records);
		// Direct and not indexed: on GLES, instance_index counts from `first` only in a direct draw.
		encoder.renderDrawRange(6, count, 0, first);
	}

	/** Begins a render pass on `view`, clearing it to the colour given or keeping what it holds. **/
	function beginPass(encoder:GpuEncoder, view:GpuTextureView, clear:Bool, r:Float, g:Float, b:Float, a:Float):Void {
		var attachment = new GpuRenderPassColorAttachment(clear ? LoadOp.Clear : LoadOp.Load, StoreOp.Store);
		attachment.viewTextureView(view);
		if (clear)
			attachment.clearValue(new GpuColor(r, g, b, a));
		var descriptor = new GpuRenderPassDescriptor();
		descriptor.addColorAttachments(attachment);
		encoder.beginRenderPass(descriptor);
	}

	/** The layer at `depth`, from 1, a texture `width` × `height` of the target's format, made or remade to fit. **/
	function layerAt(depth:Int, width:Int, height:Int):Layer {
		var at = layers[depth - 1];
		if (at != null && at.width == width && at.height == height)
			return at;
		if (at != null) {
			at.group.destroy();
			at.texture.destroy();
		}
		var size = new GpuExtent3D(width);
		size.height(height);
		var texture = device.texture(new GpuTextureDescriptor(size, format, TextureUsage.RENDER_ATTACHMENT | TextureUsage.TEXTURE_BINDING));
		var view = texture.createView(new GpuTextureViewDescriptor());
		var bindings = new GpuBindings();
		bindings.buffer(frame);
		bindings.texture(view);
		var group = device.bindGroup(layerPass.pipeline, LayerShader.FRAME_GROUP, bindings);
		bindings.destroy();
		var made:Layer = {texture: texture, view: view, group: group, width: width, height: height};
		layers[depth - 1] = made;
		return made;
	}

	/** Grows the records texture to `rows` rows, and binds each pass to it. **/
	function reserve(rows:Int):Void {
		if (rows <= recordRows)
			return;
		if (records != null)
			records.destroy();
		recordRows = rows + (rows >> 1) + 1;
		var size = new GpuExtent3D(DisplayList.ROW_TEXELS);
		size.height(recordRows);
		records = device.texture(new GpuTextureDescriptor(size, TextureFormat.Rgba32float, TextureUsage.TEXTURE_BINDING | TextureUsage.COPY_DST));
		var view = records.createView(new GpuTextureViewDescriptor());
		for (pass in passes) {
			if (pass.records != null)
				pass.records.destroy();
			var bindings = new GpuBindings();
			bindings.texture(view);
			pass.records = device.bindGroup(pass.pipeline, BoxShader.TEXTURE_records_GROUP, bindings);
			bindings.destroy();
		}
	}

	/** wgpu reports validation errors on the device, not by throwing. **/
	function failOnError(doing:String):Void {
		var error = device.takeError();
		if (error != null)
			throw 'gpu error $doing: $error';
	}
}

private typedef Layer = {
	final texture:GpuTexture;
	final view:GpuTextureView;
	final group:GpuBindGroup;
	final width:Int;
	final height:Int;
}

private typedef Pass = {
	final pipeline:GpuPipeline;
	var group:Null<GpuBindGroup>;
	/** The pass's own bind group of the records texture: an inferred layout is one pipeline's. **/
	var records:Null<GpuBindGroup>;
}
