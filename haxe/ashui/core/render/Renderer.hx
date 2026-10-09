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
	Draws a `DisplayList` with the GPU. `Offscreen` drives it, and
	`WindowedApp` through that; an app rarely makes one itself.

	A display list is the laid-out UI flattened into what to paint, in paint
	order: one record per primitive (a box, a shadow, a glyph, an image, or
	the start or end of a layer), each a fixed number of rows of four floats
	(see `ashui.layout.RecordLayout`). The records are uploaded as rows of a
	float texture, which each shader reads its instance's record from (see
	`UiFramework`), on every platform alike. Each record is an instanced
	quad of six vertices, and each run of records of one kind is one draw
	with that kind's pipeline, so paint order holds across kinds.

	Shapes are drawn from signed distances (see `Sdf`): for each pixel the
	shader works out how far it is from the shape's edge and turns that
	into coverage, so edges are anti-aliased at any size, rotation or
	corner shape without building meshes.

	A group with opacity, a filter or a drop shadow draws into a layer: a
	cleared offscreen texture the target's size, composited back over the
	group's bounds by `LayerShader`, as CSS composites one, so overlapping
	children fade or blur as one image. Layers nest, a texture per depth.

	Colours are straight alpha, blended over the target in gamma space, so
	targets should be formats without sRGB encoding. Glyphs sample the text
	engine's atlases, uploaded before each frame that changed them; images
	sample an atlas of their own, rasterized into as they appear.

	Written against hlwgpu's `gpu` package; the shaders are HXSL, so
	caribou-gpu takes the same ones. Draws as Blinc's renderer does.
**/
class Renderer {
	final device:GpuDevice;
	final frame:GpuBuffer;
	final frameBytes:haxe.io.Bytes;
	var boxes(get, never):Pass;
	var _boxes:Null<Pass> = null;
	var shadows(get, never):Pass;
	var _shadows:Null<Pass> = null;
	var text(get, never):Pass;
	var _text:Null<Pass> = null;
	var atlas:Null<GlyphAtlas> = null;
	var colorAtlas:Null<GlyphAtlas> = null;
	final glyphSampler:GpuSampler;
	var images(get, never):Pass;
	var _images:Null<Pass> = null;
	var imageAtlas:Null<ImageAtlas> = null;
	var layerPass(get, never):Pass;
	var _layerPass:Null<Pass> = null;
	/** The first pass of a layer's blur, written as it is: blending off. **/
	var blurPass(get, never):Pass;
	var _blurPass:Null<Pass> = null;
	/** The first pass of a layer's drop shadow, its alpha blurred along its rows, blending off. **/
	var shadowPass(get, never):Pass;
	var _shadowPass:Null<Pass> = null;
	/** A backdrop filter's two passes, and the copy of a frame drawn offscreen onto its target. **/
	var backdropRowsPass(get, never):Pass;
	var _backdropRowsPass:Null<Pass> = null;
	var backdropPass(get, never):Pass;
	var _backdropPass:Null<Pass> = null;
	var blitPass(get, never):Pass;
	var _blitPass:Null<Pass> = null;
	/** The frame drawn offscreen, when a backdrop filter must read what is drawn under it. **/
	var frameLayer:Null<Layer> = null;
	final format:TextureFormat;
	/** A composite record's blur, its `color.r`: its deviation in pixels. **/
	static inline var BLUR_FIELD = 8;

	/** A composite record's drop shadow colour's alpha, `via.a`: none at 0. **/
	static inline var SHADOW_ALPHA_FIELD = 55;

	/** An image's or a canvas's slot, `gradient.x`. **/
	static inline var GRADIENT_FIELD = 40;

	/** Layer textures by depth, from 1, the target's size, each with its bind group for `layerPass`. **/
	final layers:Array<Layer> = [];
	var imageRevision = -1;
	/** The atlas revisions `text`'s bind group holds views of. **/
	var textRevisions = "";
	var records:Null<GpuTexture> = null;
	var recordsView:Null<GpuTextureView> = null;
	/** Rows of the records texture, `DisplayList.RECORDS_PER_ROW` records each. **/
	var recordRows = 0;
	final passes:Array<Pass> = [];

	/**
		A renderer drawing into targets of `format`. Pick one without sRGB
		encoding: colours are already sRGB and blend as they are.
	**/
	public function new(device:GpuDevice, format:TextureFormat) {
		this.device = device;
		frameBytes = haxe.io.Bytes.alloc(BoxShader.FRAME_SIZE);
		frame = device.createBuffer(new GpuBufferDescriptor(BoxShader.FRAME_SIZE, GpuFlags.BUFFER_UNIFORM | GpuFlags.BUFFER_COPY_DST));
		var sampler = new GpuSamplerDescriptor();
		sampler.magFilter(Linear);
		sampler.minFilter(Linear);
		glyphSampler = device.sampler(sampler);
		this.format = format;
	}

	// Compile each shader once, when a display list first needs it. WGSL is a
	// generated static final string; these getters never construct shader source.
	inline function get_boxes():Pass
		return _boxes != null ? _boxes : (_boxes = pass(BoxShader.WGSL, format));

	inline function get_shadows():Pass
		return _shadows != null ? _shadows : (_shadows = pass(ShadowShader.WGSL, format));

	inline function get_text():Pass
		return _text != null ? _text : (_text = pass(TextShader.WGSL, format, false));

	inline function get_images():Pass
		return _images != null ? _images : (_images = pass(ImageShader.WGSL, format, false));

	inline function get_layerPass():Pass
		return _layerPass != null ? _layerPass : (_layerPass = pass(LayerShader.WGSL, format, false));

	inline function get_blurPass():Pass
		return _blurPass != null ? _blurPass : (_blurPass = pass(LayerBlurShader.WGSL, format, false, false));

	inline function get_shadowPass():Pass
		return _shadowPass != null ? _shadowPass : (_shadowPass = pass(LayerShadowShader.WGSL, format, false, false));

	inline function get_backdropRowsPass():Pass
		return _backdropRowsPass != null ? _backdropRowsPass : (_backdropRowsPass = pass(BackdropRowsShader.WGSL, format, false, false));

	inline function get_backdropPass():Pass
		return _backdropPass != null ? _backdropPass : (_backdropPass = pass(BackdropShader.WGSL, format, false));

	inline function get_blitPass():Pass
		return _blitPass != null ? _blitPass : (_blitPass = pass(BlitShader.WGSL, format, false, false));

	function pass(wgsl:String, format:TextureFormat, bind = true, blend = true):Pass {
		var shader = device.createShader(wgsl);
		var builder = device.pipeline();
		builder.shader(shader, "vertex", "fragment");
		builder.target(format, GpuFlags.COLOR_WRITE_ALL);
		if (blend)
			builder.blend(BlendFactor.SrcAlpha, BlendFactor.OneMinusSrcAlpha, BlendOperation.Add, BlendFactor.One, BlendFactor.OneMinusSrcAlpha,
			BlendOperation.Add);
		builder.primitive(PrimitiveTopology.TriangleList, CullMode.None, FrontFace.Ccw);
		var pipeline = builder.build();
		var error = device.takeError();
		var messages = error != null ? shader.messages() : null;
		// Pipelines retain what they need; the integer shader handle is not GC-owned.
		shader.destroy();
		if (error != null) {
			pipeline.destroy();
			throw 'gpu error building a pipeline: $messages: $error';
		}
		// An inferred layout is the pipeline's own, so each pipeline gets its own group.
		var group:Null<GpuBindGroup> = null;
		if (bind) {
			var bindings = new GpuBindings();
			bindings.buffer(frame);
			group = device.bindGroup(pipeline, BoxShader.FRAME_GROUP, bindings);
			bindings.destroy();
		}
		var made:Pass = {pipeline: pipeline, group: group, records: null};
		// Only a shader that reads records gets their bind group: the blit reads none.
		if (wgsl.indexOf("var records") >= 0) {
			passes.push(made);
			// First use can follow an earlier frame that allocated records.
			if (records != null)
				bindRecords(made);
		}
		return made;
	}

	/**
		A device from `adapter` whose memory is allocated in small blocks
		rather than large ones kept for speed, the large blocks mostly empty
		for a UI and its few textures; able to sample block-compressed
		textures where the GPU can.
	**/
	public static function requestDevice(adapter:gpu.GpuAdapter):gpu.GpuDevice {
		#if ashui_caribou
		return adapter.requestDevice().await();
		#else
		var descriptor = new gpu.GpuDeviceDescriptor();
		descriptor.memoryHints(MemoryUsage);
		// Block-compressed textures where the GPU samples them: meshes' textures take a quarter of the memory.
		if (adapter.supports(TextureCompressionBc))
			descriptor.addRequiredFeatures(TextureCompressionBc);
		return adapter.requestDeviceWith(descriptor).await();
		#end
	}

	/** Pipelines made for canvases' shaders, by their WGSL. **/
	final canvasPasses = new Map<String, Pass>();

	/** A pipeline for a canvas's `UiShader`: alpha-blended into the frame's targets, the frame uniforms and records bound; made once. **/
	public function uiPass(wgsl:String):Pass {
		var made = canvasPasses.get(wgsl);
		if (made == null)
			canvasPasses.set(wgsl, made = pass(wgsl, format));
		return made;
	}

	/** Uploads changed atlases, and binds the text pass to their current views. **/
	function syncText():Void {
		if (atlas == null) {
			atlas = new GlyphAtlas(device, false);
			colorAtlas = new GlyphAtlas(device, true);
		}
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

	/** Shared by display-list images and canvases, either of which may be drawn first. **/
	function ensureImageAtlas():ImageAtlas {
		if (imageAtlas == null)
			imageAtlas = new ImageAtlas(device);
		return imageAtlas;
	}

	/** Rasterizes the list's new images, and binds the image pass to the atlas's current view. **/
	function syncImages(list:DisplayList):Void {
		ensureImageAtlas();
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

	/**
		Draws `list` into `view`, `width` × `height` units, after clearing it
		to the given colour, or over what it holds with `keep`. `pixelWidth`
		× `pixelHeight` is the size of `view`'s texture, which layers match;
		the same as the units unless they are scaled.
	**/
	public function draw(list:DisplayList, view:GpuTextureView, width:Int, height:Int, r = 0.0, g = 0.0, b = 0.0, a = 0.0, ?pixelWidth:Int,
			?pixelHeight:Int, keep = false):Void {
		var layerWidth = pixelWidth != null ? pixelWidth : width;
		var layerHeight = pixelHeight != null ? pixelHeight : height;
		var queue = device.queue();
		frameBytes.setFloat(BoxShader.FRAME_viewport, width);
		frameBytes.setFloat(BoxShader.FRAME_viewport + 4, height);
		queue.writeBuffer(frame, 0, frameBytes, frameBytes.length);
		var offscreen = false, hasText = false, hasImages = false;
		for (i in 0...list.count)
			switch list.kind(i) {
				case DisplayList.PRIM_BACKDROP: offscreen = true;
				case DisplayList.PRIM_TEXT: hasText = true;
				case DisplayList.PRIM_IMAGE: hasImages = true;
				default:
			}
		if (hasText)
			syncText();
		if (hasImages)
			syncImages(list);
		if (list.count > 0) {
			// Whole rows: the list's bytes hold whole rows of records, so the last is complete.
			var rows = Math.ceil(list.stored / DisplayList.RECORDS_PER_ROW);
			reserve(rows);
			queue.writeTexture(records, list.bytes, DisplayList.ROW_TEXELS, rows, DisplayList.ROW_TEXELS * 16);
		}
		var encoder = device.encoder();
		// A backdrop filter reads what is drawn under it, which a window's surface does not allow:
		// such a frame is drawn into a texture of its own and copied to `view` at the end.
		// Drawn over a frame already there, it draws straight into the view: a frame texture of its own would start empty.
		if (keep)
			offscreen = false;
		if (offscreen && (frameLayer == null || frameLayer.width != layerWidth || frameLayer.height != layerHeight)) {
			if (frameLayer != null)
				destroyLayer(frameLayer);
			frameLayer = makeLayer(layerWidth, layerHeight);
		}
		var base = offscreen ? frameLayer.view : view;
		beginPass(encoder, base, !keep, r, g, b, a);
		if (list.count > 0) {
			var start = 0;
			var depth = 0;
			while (start < list.count) {
				var kind = list.kind(start);
				if (kind == DisplayList.PRIM_BACKDROP) {
					// What is under the box so far, blurred along its rows into the target's second
					// texture, then down its columns and filtered as it is drawn back over the box.
					var under = depth == 0 ? frameLayer : layers[depth - 1];
					if (under.backdropRowsGroup == null)
						under.backdropRowsGroup = layerGroup(backdropRowsPass, BackdropRowsShader.FRAME_GROUP, under.view);
					if (under.backdropGroup == null)
						under.backdropGroup = layerGroup(backdropPass, BackdropShader.FRAME_GROUP, under.rowsView);
					encoder.renderEnd();
					beginPass(encoder, under.rowsView, true, 0, 0, 0, 0);
					encoder.renderSetPipeline(backdropRowsPass.pipeline);
					encoder.renderSetBindGroup(BackdropRowsShader.FRAME_GROUP, under.backdropRowsGroup);
					encoder.renderSetBindGroup(BackdropRowsShader.TEXTURE_records_GROUP, backdropRowsPass.records);
					encoder.renderDrawRange(6, 1, 0, start);
					encoder.renderEnd();
					beginPass(encoder, under.view, false, 0, 0, 0, 0);
					encoder.renderSetPipeline(backdropPass.pipeline);
					encoder.renderSetBindGroup(BackdropShader.FRAME_GROUP, under.backdropGroup);
					encoder.renderSetBindGroup(BackdropShader.TEXTURE_records_GROUP, backdropPass.records);
					encoder.renderDrawRange(6, 1, 0, start);
					start++;
					continue;
				}
				if (kind == DisplayList.PRIM_LAYER_BEGIN) {
					// What follows draws into a cleared layer, until its composite record.
					encoder.renderEnd();
					depth++;
					beginPass(encoder, layerAt(depth, layerWidth, layerHeight).view, true, 0, 0, 0, 0);
					start++;
					continue;
				}
				if (kind == DisplayList.PRIM_LAYER) {
					// Back to the layer or target under it, keeping what it holds, to composite this one;
					// a blurred one blurs along its rows into its second texture first.
					encoder.renderEnd();
					var inner = layers[depth - 1];
					var blurred = list.get(start, BLUR_FIELD) > 0;
					if (list.get(start, SHADOW_ALPHA_FIELD) > 0) {
						if (inner.shadowPassGroup == null)
							inner.shadowPassGroup = layerGroup(shadowPass, LayerShadowShader.FRAME_GROUP, inner.view);
						beginPass(encoder, inner.shadowView, true, 0, 0, 0, 0);
						encoder.renderSetPipeline(shadowPass.pipeline);
						encoder.renderSetBindGroup(LayerShadowShader.FRAME_GROUP, inner.shadowPassGroup);
						encoder.renderSetBindGroup(LayerShadowShader.TEXTURE_records_GROUP, shadowPass.records);
						encoder.renderDrawRange(6, 1, 0, start);
						encoder.renderEnd();
					}
					if (blurred) {
						if (inner.blurGroup == null)
							inner.blurGroup = layerGroup(blurPass, LayerBlurShader.FRAME_GROUP, inner.view);
						beginPass(encoder, inner.rowsView, true, 0, 0, 0, 0);
						encoder.renderSetPipeline(blurPass.pipeline);
						encoder.renderSetBindGroup(LayerBlurShader.FRAME_GROUP, inner.blurGroup);
						encoder.renderSetBindGroup(LayerBlurShader.TEXTURE_records_GROUP, blurPass.records);
						encoder.renderDrawRange(6, 1, 0, start);
						encoder.renderEnd();
					}
					depth--;
					beginPass(encoder, depth == 0 ? base : layers[depth - 1].view, false, 0, 0, 0, 0);
					if (inner.shadowGroup == null) {
						var bindings = new GpuBindings();
						bindings.texture(inner.shadowView);
						bindings.sampler(glyphSampler);
						inner.shadowGroup = device.bindGroup(layerPass.pipeline, LayerShader.TEXTURE_shadow_GROUP, bindings);
						bindings.destroy();
					}
					if (blurred && inner.rowsGroup == null)
						inner.rowsGroup = layerGroup(layerPass, LayerShader.FRAME_GROUP, inner.rowsView);
					if (!blurred && inner.group == null)
						inner.group = layerGroup(layerPass, LayerShader.FRAME_GROUP, inner.view);
					encoder.renderSetPipeline(layerPass.pipeline);
					encoder.renderSetBindGroup(LayerShader.FRAME_GROUP, blurred ? inner.rowsGroup : inner.group);
					encoder.renderSetBindGroup(LayerShader.TEXTURE_shadow_GROUP, inner.shadowGroup);
					encoder.renderSetBindGroup(LayerShader.TEXTURE_records_GROUP, layerPass.records);
					encoder.renderDrawRange(6, 1, 0, start);
					start++;
					continue;
				}
				if (kind == DisplayList.PRIM_CANVAS) {
					paintCanvas(encoder, list, start, width, height, layerWidth, layerHeight, depth == 0 ? base : layers[depth - 1].view);
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
		if (offscreen) {
			if (frameLayer.blitGroup == null)
				frameLayer.blitGroup = layerGroup(blitPass, BlitShader.FRAME_GROUP, frameLayer.view, false);
			beginPass(encoder, view, true, r, g, b, a);
			encoder.renderSetPipeline(blitPass.pipeline);
			encoder.renderSetBindGroup(BlitShader.FRAME_GROUP, frameLayer.blitGroup);
			encoder.renderDrawRange(6, 1, 0, 0);
			encoder.renderEnd();
		}
		encoder.submit(queue);
		failOnError("drawing");
		// Canvases this frame left unpainted, scrolled away or hidden, give up their 3D layers after a while.
		ScenePainter.sweep();
	}

	/**
		Hands the pass to the canvas of the record at `at`, scissored to its
		clipped box, then sets the scissor back to the whole target. Nothing
		else needs restoring: each run sets its own pipeline and bindings.
	**/
	function paintCanvas(encoder:GpuEncoder, list:DisplayList, at:Int, width:Int, height:Int, targetWidth:Int, targetHeight:Int,
			target:GpuTextureView):Void {
		var canvas = ashui.ui.Canvas.at(Std.int(list.get(at, GRADIENT_FIELD)));
		if (canvas == null)
			return;
		inline function f(row:Int, i:Int)
			return list.get(at, row * 4 + i);
		var w = f(0, 2), h = f(0, 3);
		var transform = new ashui.draw.Affine(f(15, 0), f(15, 1), f(15, 2), f(15, 3), f(0, 0), f(0, 1));
		// The box on screen, cut by the screen clip and the local one, bit 1 and bit 2 of the clips.
		var box = bounding(transform, 0, 0, w, h);
		var clips = Std.int(f(11, 2));
		if (clips & 1 != 0)
			box = intersect(box, [f(8, 0), f(8, 1), f(8, 0) + f(8, 2), f(8, 1) + f(8, 3)]);
		if (clips & 2 != 0)
			box = intersect(box, bounding(transform, f(6, 0), f(6, 1), f(6, 2), f(6, 3)));
		var ratio = targetWidth / width;
		var x0 = Std.int(Math.max(0, Math.floor(box[0] * ratio))), y0 = Std.int(Math.max(0, Math.floor(box[1] * ratio)));
		var x1 = Std.int(Math.min(targetWidth, Math.ceil(box[2] * ratio))), y1 = Std.int(Math.min(targetHeight, Math.ceil(box[3] * ratio)));
		if (x1 <= x0 || y1 <= y0)
			return;
		encoder.renderSetScissorRect(x0, y0, x1 - x0, y1 - y0);
		canvas.paintWith(new CanvasFrame(this, device, encoder, format, at, w, h, transform, transform.scale() * ratio, ratio, [x0, y0, x1 - x0, y1 - y0], target));
		encoder.renderSetScissorRect(0, 0, targetWidth, targetHeight);
	}

	/** The box `[left, top, right, bottom]` around the rect `x, y, w, h` through `m`. **/
	static function bounding(m:ashui.draw.Affine, x:Float, y:Float, w:Float, h:Float):Array<Float> {
		var xs = [m.x(x, y), m.x(x + w, y), m.x(x, y + h), m.x(x + w, y + h)];
		var ys = [m.y(x, y), m.y(x + w, y), m.y(x, y + h), m.y(x + w, y + h)];
		return [
			Math.min(Math.min(xs[0], xs[1]), Math.min(xs[2], xs[3])), Math.min(Math.min(ys[0], ys[1]), Math.min(ys[2], ys[3])),
			Math.max(Math.max(xs[0], xs[1]), Math.max(xs[2], xs[3])), Math.max(Math.max(ys[0], ys[1]), Math.max(ys[2], ys[3]))
		];
	}

	static function intersect(a:Array<Float>, b:Array<Float>):Array<Float>
		return [Math.max(a[0], b[0]), Math.max(a[1], b[1]), Math.min(a[2], b[2]), Math.min(a[3], b[3])];

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

	/** The layer at `depth`, from 1, a texture `width` × `height` pixels in the target's format, made or remade to fit. **/
	function layerAt(depth:Int, width:Int, height:Int):Layer {
		var at = layers[depth - 1];
		if (at != null && at.width == width && at.height == height)
			return at;
		if (at != null)
			destroyLayer(at);
		var made = makeLayer(width, height);
		layers[depth - 1] = made;
		return made;
	}

	function destroyLayer(at:Layer):Void {
		for (g in [
			at.group, at.rowsGroup, at.blurGroup, at.shadowPassGroup, at.shadowGroup, at.backdropRowsGroup, at.backdropGroup, at.blitGroup
		])
			if (g != null)
				g.destroy();
		at.view.destroy();
		at.rowsView.destroy();
		at.shadowView.destroy();
		at.texture.destroy();
		at.rows.destroy();
		at.shadow.destroy();
	}

	/** A target `width` × `height` pixels in the target's format, with the textures and bindings its passes use. **/
	function makeLayer(width:Int, height:Int):Layer {
		var size = new GpuExtent3D(width);
		size.height(height);
		function target():GpuTexture
			return device.texture(new GpuTextureDescriptor(size, format, GpuFlags.TEXTURE_RENDER_ATTACHMENT | GpuFlags.TEXTURE_BINDING));
		var texture = target();
		var view = texture.createView(new GpuTextureViewDescriptor());
		var rows = target();
		var rowsView = rows.createView(new GpuTextureViewDescriptor());
		var shadow = target();
		var shadowView = shadow.createView(new GpuTextureViewDescriptor());
		return {
			texture: texture,
			view: view,
			group: null,
			rows: rows,
			rowsView: rowsView,
			rowsGroup: null,
			blurGroup: null,
			shadow: shadow,
			shadowView: shadowView,
			shadowPassGroup: null,
			shadowGroup: null,
			backdropRowsGroup: null,
			backdropGroup: null,
			blitGroup: null,
			width: width,
			height: height
		};
	}

	/** Bind a layer only when its effect is first drawn; inferred layouts belong to one pipeline. **/
	function layerGroup(pass:Pass, frameGroup:Int, view:GpuTextureView, sampled = true):GpuBindGroup {
		var bindings = new GpuBindings();
		bindings.buffer(frame);
		bindings.texture(view);
		if (sampled)
			bindings.sampler(glyphSampler);
		var made = device.bindGroup(pass.pipeline, frameGroup, bindings);
		bindings.destroy();
		return made;
	}

	/** Grows the records texture to `rows` rows, and binds each pass to it. **/
	function reserve(rows:Int):Void {
		if (rows <= recordRows)
			return;
		if (records != null) {
			recordsView.destroy();
			records.destroy();
		}
		recordRows = rows + (rows >> 1) + 1;
		var size = new GpuExtent3D(DisplayList.ROW_TEXELS);
		size.height(recordRows);
		records = device.texture(new GpuTextureDescriptor(size, TextureFormat.Rgba32float, GpuFlags.TEXTURE_BINDING | GpuFlags.TEXTURE_COPY_DST));
		recordsView = records.createView(new GpuTextureViewDescriptor());
		for (pass in passes)
			bindRecords(pass);
	}

	/** Binds `pass` to the records texture as it is now. **/
	function bindRecords(pass:Pass):Void {
		if (pass.records != null)
			pass.records.destroy();
		var bindings = new GpuBindings();
		bindings.texture(recordsView);
		pass.records = device.bindGroup(pass.pipeline, BoxShader.TEXTURE_records_GROUP, bindings);
		bindings.destroy();
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
	/** `layerPass`'s bindings of the layer itself. **/
	var group:Null<GpuBindGroup>;
	/** The layer blurred along its rows, the first pass of a blur. **/
	final rows:GpuTexture;
	final rowsView:GpuTextureView;
	/** `layerPass`'s bindings of `rows`, and `blurPass`'s of the layer. **/
	var rowsGroup:Null<GpuBindGroup>;
	var blurGroup:Null<GpuBindGroup>;
	/** The layer's alpha blurred along its rows for its drop shadow, `shadowPass`'s bindings of the layer, and `layerPass`'s of the shadow. **/
	final shadow:GpuTexture;
	final shadowView:GpuTextureView;
	var shadowPassGroup:Null<GpuBindGroup>;
	var shadowGroup:Null<GpuBindGroup>;
	/** A backdrop filter's bindings: of the target itself for its rows, and of its rows for the columns; and the blit's. **/
	var backdropRowsGroup:Null<GpuBindGroup>;
	var backdropGroup:Null<GpuBindGroup>;
	var blitGroup:Null<GpuBindGroup>;
	final width:Int;
	final height:Int;
}

/** A pipeline and its bind groups: the frame uniforms, and the records texture for a shader that reads records. **/
typedef Pass = {
	final pipeline:GpuPipeline;
	var group:Null<GpuBindGroup>;
	/** The pass's own bind group of the records texture: an inferred layout is one pipeline's. **/
	var records:Null<GpuBindGroup>;
}
