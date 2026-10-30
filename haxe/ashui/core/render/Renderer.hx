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
	Renders a `DisplayList` on the GPU. Usually created by `Offscreen`,
	which also supplies rendering for `WindowedApp`.

	The display list stores paint-ordered records for boxes, shadows, glyphs,
	images and layer boundaries. Records use rows of four floats (see
	`RecordLayout`) uploaded to a texture. Each primitive is a six-vertex
	instanced quad. Consecutive primitives of the same kind share a draw
	call and pipeline, preserving paint order across kinds.

	Shapes use signed-distance coverage for antialiased edges at any scale,
	rotation or corner shape. See `Sdf`.

	Groups with opacity, filters or drop shadows render into offscreen layers,
	then composite over their bounds with `LayerShader`. This applies effects
	to overlapping children as one image. Nested groups use one texture per depth.

	Colors use straight alpha and gamma-space blending; targets should use
	formats without sRGB encoding. Glyph atlases upload only when changed.
	Images use a separate atlas populated on demand.

	Uses hlwgpu's `gpu` API and HXSL shaders, also supported by caribou-gpu.
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
	var imageResidency = 0;
	var bitmapDisposals = 0;
	var svgDisposals = 0;
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
	var liquidBackdropPass(get, never):Pass;
	var _liquidBackdropPass:Null<Pass> = null;
	var blitPass(get, never):Pass;
	var _blitPass:Null<Pass> = null;

	/** The frame drawn offscreen, when a backdrop filter must read what is drawn under it. **/
	var frameLayer:Null<Layer> = null;

	// Filters finish before another layer uses scratch space, so all depths share it.
	var rows:Null<LayerTarget> = null;
	var shadow:Null<LayerTarget> = null;
	var rowsGroup:Null<GpuBindGroup> = null;
	var backdropGroup:Null<GpuBindGroup> = null;
	var liquidBackdropGroup:Null<GpuBindGroup> = null;
	var shadowGroup:Null<GpuBindGroup> = null;
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
		MeshTextures.prepare(device);
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

	inline function get_liquidBackdropPass():Pass
		return _liquidBackdropPass != null ? _liquidBackdropPass : (_liquidBackdropPass = pass(LiquidBackdropShader.WGSL, format, false));

	inline function get_blitPass():Pass
		return _blitPass != null ? _blitPass : (_blitPass = pass(BlitShader.WGSL, format, false, false));

	/**
		A pipeline for a canvas's `UiShader` that writes premultiplied colour, blended into the target as `mode` says: the
		frame uniforms and records bound; made once for each shader and mode.
	**/
	public function blendedPass(wgsl:String, mode:ashui.draw.BlendMode):Pass {
		var key = '${(mode : Int)}:$wgsl';
		var made = canvasPasses.get(key);
		if (made == null)
			canvasPasses.set(key, made = pass(wgsl, format, true, true, mode));
		return made;
	}

	/** `mode`'s blend of a premultiplied source: its colour and alpha factors and the colour operation. **/
	static function blendOf(mode:ashui.draw.BlendMode):{src:BlendFactor, dst:BlendFactor, op:BlendOperation, alphaSrc:BlendFactor, alphaDst:BlendFactor} {
		var over = {src: BlendFactor.One, dst: BlendFactor.OneMinusSrcAlpha, op: BlendOperation.Add, alphaSrc: BlendFactor.One, alphaDst: BlendFactor.OneMinusSrcAlpha};
		return switch mode {
			case Add: {src: BlendFactor.One, dst: BlendFactor.One, op: BlendOperation.Add, alphaSrc: over.alphaSrc, alphaDst: over.alphaDst};
			case Subtract: {src: BlendFactor.One, dst: BlendFactor.One, op: BlendOperation.ReverseSubtract, alphaSrc: over.alphaSrc, alphaDst: over.alphaDst};
			case Multiply: {src: BlendFactor.Dst, dst: BlendFactor.OneMinusSrcAlpha, op: BlendOperation.Add, alphaSrc: over.alphaSrc, alphaDst: over.alphaDst};
			case Screen: {src: BlendFactor.One, dst: BlendFactor.OneMinusSrc, op: BlendOperation.Add, alphaSrc: over.alphaSrc, alphaDst: over.alphaDst};
			case _: over;
		}
	}

	function pass(wgsl:String, format:TextureFormat, bind = true, blend = true, ?premultiplied:ashui.draw.BlendMode):Pass {
		var shader = device.createShader(wgsl);
		var builder = device.pipeline();
		builder.shader(shader, "vertex", "fragment");
		builder.target(format, GpuFlags.COLOR_WRITE_ALL);
		if (blend && premultiplied != null) {
			var b = blendOf(premultiplied);
			builder.blend(b.src, b.dst, b.op, b.alphaSrc, b.alphaDst, BlendOperation.Add);
		} else if (blend)
			builder.blend(BlendFactor.SrcAlpha, BlendFactor.OneMinusSrcAlpha, BlendOperation.Add, BlendFactor.One, BlendFactor.OneMinusSrcAlpha,
				BlendOperation.Add);
		builder.primitive(PrimitiveTopology.TriangleList, CullMode.None, FrontFace.Ccw);
		var pipeline = builder.build();
		// A page sends a frame's commands together, and reading the error here, in the frame that first
		// needs the pipeline, would send them early: the frame's texture would be gone by its submit.
		// The frame's own check reports it.
		#if !wasm
		var error = device.takeError();
		var messages = error != null ? shader.messages() : null;
		#end
		// Pipelines retain what they need; the integer shader handle is not GC-owned.
		shader.destroy();
		#if !wasm
		if (error != null) {
			pipeline.destroy();
			throw 'gpu error building a pipeline: $messages: $error';
		}
		#end
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
		var descriptor = new gpu.GpuDeviceDescriptor();
		descriptor.memoryHints(MemoryUsage);
		// Block-compressed textures where the GPU samples them: meshes' textures take a quarter of the memory.
		if (adapter.supports(TextureCompressionBc))
			descriptor.addRequiredFeatures(TextureCompressionBc);
		// A texture side as large as the GPU takes, not the 8192 a device gets unless it asks.
		var most = haxe.Int64.toInt(adapter.limit(MaxTextureDimension2D));
		if (most > maxTexture) {
			descriptor.addRequiredLimits(MaxTextureDimension2D, most);
			maxTexture = most;
		}
		return adapter.requestDeviceWith(descriptor).await();
	}

	/** The most a texture side may be on the device `requestDevice` made, 8192 until then; what a canvas's triangle table and a mesh's textures are held to. **/
	public static var maxTexture = 8192;

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

	/** Whether a frame like the last but for a part of it is drawn as that part; `ASHUI_DAMAGE=0` turns it off, for comparing. **/
	public var damage = Sys.getEnv("ASHUI_DAMAGE") != "0";

	/** The layers the last frame drew, each a render pass over a texture of the window's size: a group at some opacity over more than one painted node, a filter, a mask. **/
	public var layerRecords(default, null) = 0;

	/** How the last frame was drawn: `full`, `none` for one that drew nothing, or `x,y,w,h` of the part drawn again, in target pixels. **/
	public var drew(default, null) = "";

	/** Whether `frameLayer` holds the last frame whole, and the list, sizes and colour it was drawn from. **/
	var frameValid = false;

	var lastList:Null<haxe.io.Bytes> = null;
	var lastCount = 0;
	var lastStored = 0;
	var lastWidth = 0;
	var lastHeight = 0;
	var lastLayerWidth = 0;
	var lastLayerHeight = 0;
	var lastClear = "";

	/** The window's colour as one texel, to take a part of a frame back to it. **/
	var clearTexture:Null<GpuTexture> = null;

	var clearView:Null<GpuTextureView> = null;
	var clearBind:Null<GpuBindGroup> = null;
	var clearKey = "";
	var clearPass(get, never):Pass;
	var _clearPass:Null<Pass> = null;

	inline function get_clearPass():Pass
		return _clearPass != null ? _clearPass : (_clearPass = pass(ClearShader.WGSL, format, false, false));

	/** The bind group that fills with `r, g, b, a`, its texel written when the colour is new. **/
	function clearGroup(r:Float, g:Float, b:Float, a:Float):GpuBindGroup {
		if (clearTexture == null) {
			var size = new GpuExtent3D(1);
			size.height(1);
			clearTexture = device.texture(new GpuTextureDescriptor(size, TextureFormat.Rgba32float, GpuFlags.TEXTURE_BINDING | GpuFlags.TEXTURE_COPY_DST));
			clearView = clearTexture.createView(new GpuTextureViewDescriptor());
			clearBind = layerGroup(clearPass, ClearShader.FRAME_GROUP, clearView, false);
		}
		var key = colourKey(r, g, b, a);
		if (key != clearKey) {
			var bytes = haxe.io.Bytes.alloc(16);
			bytes.setFloat(0, r);
			bytes.setFloat(4, g);
			bytes.setFloat(8, b);
			bytes.setFloat(12, a);
			device.queue().writeTexture(clearTexture, bytes, 1, 1, 16);
			clearKey = key;
		}
		return clearBind;
	}

	static function colourKey(r:Float, g:Float, b:Float, a:Float):String
		return '$r/$g/$b/$a';

	/** Begins a pass on `view` that keeps what it holds, drawing only inside `region` (target pixels) when it is given. **/
	function continuePass(encoder:GpuEncoder, view:GpuTextureView, region:Null<Array<Int>>):Void {
		beginPass(encoder, view, false, 0, 0, 0, 0);
		if (region != null)
			encoder.renderSetScissorRect(region[0], region[1], region[2], region[3]);
	}

	/**
		Calculates frame damage from changed records and canvases, then expands
		it to include overlapping content and dependent effects.

		Returns null when a full redraw is required: no previous frame, changed
		size or clear color, a different record count, layers, or a large dirty
		area. A result with `rect=null` means nothing changed.
	**/
	function planDamage(list:DisplayList, width:Int, height:Int, layerWidth:Int, layerHeight:Int, r:Float, g:Float, b:Float, a:Float):Null<Damage> {
		var RB = DisplayList.RECORD_BYTES;
		if (!damage || !frameValid || a < 1 || frameLayer == null || lastList == null || list.count != lastCount || list.stored != lastStored || width != lastWidth
			|| height != lastHeight || layerWidth != lastLayerWidth || layerHeight != lastLayerHeight || frameLayer.width != layerWidth
			|| frameLayer.height != layerHeight || colourKey(r, g, b, a) != lastClear)
			return null;
		for (i in 0...list.count) {
			var kind = list.kind(i);
			if (kind == DisplayList.PRIM_LAYER_BEGIN || kind == DisplayList.PRIM_LAYER)
				return null;
		}
		var ratio = layerWidth / width;
		var now:hl.Bytes = list.bytes, was:hl.Bytes = lastList;
		var all = list.stored * RB, own = list.count * RB;
		// The points of polygon clips follow the records, and anything that moves them is not a change of a record.
		if (all > own && now.compare(own, was, own, all - own) != 0)
			return null;
		// The boxes of what changed: each record that differs, before and after, and each canvas that draws something new.
		var boxes:Array<Array<Float>> = [];
		var changed = now.compare(0, was, 0, own) != 0;
		if (changed)
			for (i in 0...list.count)
				if (now.compare(i * RB, was, i * RB, RB) != 0) {
					boxes.push(recordBox(list.bytes, i, ratio));
					boxes.push(recordBox(lastList, i, ratio));
				}
		// A canvas draws as its records say, and as its own drawing does, which they do not.
		var canvasBoxes:Array<Null<Array<Float>>> = [];
		for (i in 0...list.count)
			if (list.kind(i) == DisplayList.PRIM_CANVAS) {
				var canvas = canvasBox(list, i, width, height, layerWidth, layerHeight);
				canvasBoxes[i] = canvas == null ? null : [canvas.x0, canvas.y0, canvas.x1, canvas.y1];
				if (canvas != null && canvas.canvas.changed(canvas.transform, ratio, ensureImageAtlas().revision))
					boxes.push(canvasBoxes[i]);
			}
		if (boxes.length == 0)
			return {rects: [], visible: []};
		mergeBoxes(boxes);
		// A backdrop filter reads what is under it, a blur's reach beyond its box: where it touches a part, all of that is drawn again.
		var grown = true, rounds = 0;
		while (grown && rounds++ < 6) {
			grown = false;
			for (i in 0...list.count)
				if (list.kind(i) == DisplayList.PRIM_BACKDROP) {
					var box = recordBox(list.bytes, i, ratio);
					// The record's deviation is in target pixels; the blur reads three of them each side.
					var reach = list.get(i, 8) * 3 + 2;
					for (part in boxes)
						if (box[0] < part[2] && box[2] > part[0] && box[1] < part[3] && box[3] > part[1]
							&& (box[0] - reach < part[0] || box[1] - reach < part[1] || box[2] + reach > part[2] || box[3] + reach > part[3])) {
							part[0] = Math.min(part[0], box[0] - reach);
							part[1] = Math.min(part[1], box[1] - reach);
							part[2] = Math.max(part[2], box[2] + reach);
							part[3] = Math.max(part[3], box[3] + reach);
							grown = true;
						}
				}
			if (grown)
				mergeBoxes(boxes);
		}
		if (grown)
			return null;
		// Few enough parts to draw each as a part: the two nearest are one when there are more.
		while (boxes.length > MOST_PARTS) {
			var a = 0, b = 1, least = 1e30;
			for (x in 0...boxes.length)
				for (y in x + 1...boxes.length) {
					var size = unionArea(boxes[x], boxes[y]);
					if (size < least) {
						least = size;
						a = x;
						b = y;
					}
				}
			boxes[a] = unite(boxes[a], boxes[b]);
			boxes.splice(b, 1);
			mergeBoxes(boxes);
		}
		// A pixel's edge is anti-aliased past the box it is drawn in.
		var rects:Array<Array<Int>> = [], area = 0;
		for (part in boxes) {
			var x0 = Std.int(Math.max(0, Math.floor(part[0]) - 4)), y0 = Std.int(Math.max(0, Math.floor(part[1]) - 4));
			var x1 = Std.int(Math.min(layerWidth, Math.ceil(part[2]) + 4)), y1 = Std.int(Math.min(layerHeight, Math.ceil(part[3]) + 4));
			if (x1 > x0 && y1 > y0) {
				rects.push([x0, y0, x1 - x0, y1 - y0]);
				area += (x1 - x0) * (y1 - y0);
			}
		}
		if (rects.length == 0)
			return {rects: [], visible: []};
		if (area > 0.6 * layerWidth * layerHeight)
			return null;
		var visible = [];
		for (rect in rects) {
			var touching = [];
			for (i in 0...list.count) {
				var box = canvasBoxes[i] != null ? canvasBoxes[i] : list.kind(i) == DisplayList.PRIM_CANVAS ? null : recordBox(list.bytes, i, ratio);
				touching.push(box != null && box[0] < rect[0] + rect[2] && box[2] > rect[0] && box[1] < rect[1] + rect[3] && box[3] > rect[1]);
			}
			visible.push(touching);
		}
		return {rects: rects, visible: visible};
	}

	/** The most parts of a frame drawn again, one after another in a pass. **/
	static inline var MOST_PARTS = 4;

	static function unite(a:Array<Float>, b:Array<Float>):Array<Float>
		return [Math.min(a[0], b[0]), Math.min(a[1], b[1]), Math.max(a[2], b[2]), Math.max(a[3], b[3])];

	static function unionArea(a:Array<Float>, b:Array<Float>):Float
		return (Math.max(a[2], b[2]) - Math.min(a[0], b[0])) * (Math.max(a[3], b[3]) - Math.min(a[1], b[1]));

	/** Joins boxes that overlap or lie close, or that one box would hold with little more room, until none do. **/
	static function mergeBoxes(boxes:Array<Array<Float>>):Void {
		var again = true;
		while (again) {
			again = false;
			var i = 0;
			while (i < boxes.length) {
				var j = i + 1;
				while (j < boxes.length) {
					var a = boxes[i], b = boxes[j];
					var close = a[0] - 8 < b[2] && a[2] + 8 > b[0] && a[1] - 8 < b[3] && a[3] + 8 > b[1];
					var areas = (a[2] - a[0]) * (a[3] - a[1]) + (b[2] - b[0]) * (b[3] - b[1]);
					if (close || unionArea(a, b) < areas * 1.3) {
						boxes[i] = unite(a, b);
						boxes.splice(j, 1);
						again = true;
					} else
						j++;
				}
				i++;
			}
		}
	}

	/** The box `[left, top, right, bottom]`, in target pixels, record `i` of `bytes` draws in, grown by what its edge and its shadow reach. **/
	function recordBox(bytes:haxe.io.Bytes, i:Int, ratio:Float):Array<Float> {
		var at = i * DisplayList.RECORD_BYTES;
		inline function f(row:Int, k:Int)
			return bytes.getFloat(at + (row * 4 + k) * 4);
		var grow = 2.0;
		if (Std.int(f(11, 0)) == DisplayList.PRIM_SHADOW)
			grow += f(6, 2) * 3 + Math.abs(f(6, 0)) + Math.abs(f(6, 1)) + Math.max(f(6, 3), 0) + 1;
		var box = bounding(new ashui.draw.Affine(f(15, 0), f(15, 1), f(15, 2), f(15, 3), f(0, 0), f(0, 1)), -grow, -grow, f(0, 2) + grow * 2, f(0, 3) + grow * 2);
		return [box[0] * ratio, box[1] * ratio, box[2] * ratio, box[3] * ratio];
	}

	/** Takes the frame just drawn as the one the next may be drawn from, or forgets it when it cannot be. **/
	function rememberFrame(list:DisplayList, width:Int, height:Int, layerWidth:Int, layerHeight:Int, r:Float, g:Float, b:Float, a:Float, held:Bool):Void {
		if (!damage || !held || a < 1) {
			frameValid = false;
			return;
		}
		var size = list.stored * DisplayList.RECORD_BYTES;
		if (lastList == null || lastList.length < size)
			lastList = haxe.io.Bytes.alloc(size + (size >> 1));
		lastList.blit(0, list.bytes, 0, size);
		lastCount = list.count;
		lastStored = list.stored;
		lastWidth = width;
		lastHeight = height;
		lastLayerWidth = layerWidth;
		lastLayerHeight = layerHeight;
		lastClear = colourKey(r, g, b, a);
		frameValid = true;
	}

	/**
		Draws `list` into `view`, `width` × `height` units, after clearing it
		to the given colour, or over what it holds with `keep`. `pixelWidth`
		× `pixelHeight` is the size of `view`'s texture, which layers match;
		the same as the units unless they are scaled.
	**/
	public function draw(list:DisplayList, view:GpuTextureView, width:Int, height:Int, r = 0.0, g = 0.0, b = 0.0, a = 0.0, ?pixelWidth:Int, ?pixelHeight:Int,
			keep = false):Void {
		if (imageResidency != ashui.ui.ImageResidency.revision || bitmapDisposals != ashui.types.Bitmap.disposalRevision
			|| svgDisposals != ashui.svg.SvgDocument.disposalRevision) {
			imageResidency = ashui.ui.ImageResidency.revision;
			bitmapDisposals = ashui.types.Bitmap.disposalRevision;
			svgDisposals = ashui.svg.SvgDocument.disposalRevision;
			if (imageAtlas != null) imageAtlas.reset(true);
			if (images.group != null) { images.group.destroy(); images.group = null; }
			imageRevision = -1;
			frameValid = false;
		}
		var layerWidth = pixelWidth != null ? pixelWidth : width;
		var layerHeight = pixelHeight != null ? pixelHeight : height;
		var queue = device.queue();
		frameBytes.setFloat(BoxShader.FRAME_viewport, width);
		frameBytes.setFloat(BoxShader.FRAME_viewport + 4, height);
		queue.writeBuffer(frame, 0, frameBytes, frameBytes.length);
		var offscreen = false, hasText = false, hasImages = false;
		layerRecords = 0;
		for (i in 0...list.count)
			switch list.kind(i) {
				case DisplayList.PRIM_LAYER_BEGIN:
					layerRecords++;
				case DisplayList.PRIM_BACKDROP:
					offscreen = true;
				case DisplayList.PRIM_TEXT:
					hasText = true;
				case DisplayList.PRIM_IMAGE:
					hasImages = true;
				default:
			}
		if (hasText)
			syncText();
		if (hasImages)
			syncImages(list);
		// A frame like the last but for a part of it is drawn as that part, over what the last frame left.
		var damaged:Null<Damage> = offscreen && !keep ? planDamage(list, width, height, layerWidth, layerHeight, r, g, b, a) : null;
		if (list.count > 0 && !(damaged != null && damaged.rects.length == 0)) {
			// Whole rows: the list's bytes hold whole rows of records, so the last is complete.
			var rows = Math.ceil(list.stored / DisplayList.RECORDS_PER_ROW);
			reserve(rows);
			sendRecords(queue, list.bytes, rows);
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
		drew = damaged == null ? "full" : damaged.rects.length == 0 ? "none" : [for (rect in damaged.rects) rect.join(",")].join(" ");
		if (damaged == null) {
			beginPass(encoder, base, !keep, r, g, b, a);
			drawRecords(encoder, list, base, width, height, layerWidth, layerHeight, null, null);
			encoder.renderEnd();
		} else if (damaged.rects.length > 0) {
			// One pass, its scissor moved from part to part: each is taken back to the window's colour and what touches it is drawn again.
			continuePass(encoder, base, damaged.rects[0]);
			var clear = clearGroup(r, g, b, a);
			for (k in 0...damaged.rects.length) {
				var rect = damaged.rects[k];
				encoder.renderSetScissorRect(rect[0], rect[1], rect[2], rect[3]);
				encoder.renderSetPipeline(clearPass.pipeline);
				encoder.renderSetBindGroup(ClearShader.FRAME_GROUP, clear);
				encoder.renderDrawRange(6, 1, 0, 0);
				drawRecords(encoder, list, base, width, height, layerWidth, layerHeight, damaged.visible[k], rect);
			}
			encoder.renderEnd();
		}
		rememberFrame(list, width, height, layerWidth, layerHeight, r, g, b, a, offscreen && !keep);
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
		MeshTextures.startCompressions();
		// Canvases this frame left unpainted, scrolled away or hidden, give up their 3D layers after a while.
		ScenePainter.sweep();
	}

	/**
		Draws the records of `list` into the pass begun on `base`, each run of one kind as one draw, backdrops and layers as
		their passes: all of them, or those `visible` marks, inside `region`, a rect of the target's pixels the pass's scissor is set to.
	**/
	function drawRecords(encoder:GpuEncoder, list:DisplayList, base:GpuTextureView, width:Int, height:Int, layerWidth:Int, layerHeight:Int,
			visible:Null<Array<Bool>>, region:Null<Array<Int>>):Void {
		if (list.count > 0) {
			var start = 0;
			var depth = 0;
			while (start < list.count) {
				if (visible != null && !visible[start]) {
					start++;
					continue;
				}
				var kind = list.kind(start);
				if (kind == DisplayList.PRIM_BACKDROP) {
					// What is under the box so far, blurred along its rows into the target's second
					// texture, then down its columns and filtered as it is drawn back over the box.
					var under = depth == 0 ? frameLayer : layers[depth - 1];
					if (under.backdropRowsGroup == null)
						under.backdropRowsGroup = layerGroup(backdropRowsPass, BackdropRowsShader.FRAME_GROUP, under.view);
					var blurredRows = reserveRows(layerWidth, layerHeight);
					// Liquid glass, with its lens, is a pipeline of its own: one with none does not make it.
					var liquid = list.get(start, GRADIENT_FIELD) > 0.5;
					if (liquid ? liquidBackdropGroup == null : backdropGroup == null) {
						if (liquid)
							liquidBackdropGroup = layerGroup(liquidBackdropPass, LiquidBackdropShader.FRAME_GROUP, blurredRows.view);
						else
							backdropGroup = layerGroup(backdropPass, BackdropShader.FRAME_GROUP, blurredRows.view);
					}
					encoder.renderEnd();
					beginPass(encoder, blurredRows.view, true, 0, 0, 0, 0);
					encoder.renderSetPipeline(backdropRowsPass.pipeline);
					encoder.renderSetBindGroup(BackdropRowsShader.FRAME_GROUP, under.backdropRowsGroup);
					encoder.renderSetBindGroup(BackdropRowsShader.TEXTURE_records_GROUP, backdropRowsPass.records);
					encoder.renderDrawRange(6, 1, 0, start);
					encoder.renderEnd();
					continuePass(encoder, under.view, region);
					if (liquid) {
						encoder.renderSetPipeline(liquidBackdropPass.pipeline);
						encoder.renderSetBindGroup(LiquidBackdropShader.FRAME_GROUP, liquidBackdropGroup);
						encoder.renderSetBindGroup(LiquidBackdropShader.TEXTURE_records_GROUP, liquidBackdropPass.records);
					} else {
						encoder.renderSetPipeline(backdropPass.pipeline);
						encoder.renderSetBindGroup(BackdropShader.FRAME_GROUP, backdropGroup);
						encoder.renderSetBindGroup(BackdropShader.TEXTURE_records_GROUP, backdropPass.records);
					}
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
						beginPass(encoder, reserveShadow(layerWidth, layerHeight).view, true, 0, 0, 0, 0);
						encoder.renderSetPipeline(shadowPass.pipeline);
						encoder.renderSetBindGroup(LayerShadowShader.FRAME_GROUP, inner.shadowPassGroup);
						encoder.renderSetBindGroup(LayerShadowShader.TEXTURE_records_GROUP, shadowPass.records);
						encoder.renderDrawRange(6, 1, 0, start);
						encoder.renderEnd();
					}
					if (blurred) {
						if (inner.blurGroup == null)
							inner.blurGroup = layerGroup(blurPass, LayerBlurShader.FRAME_GROUP, inner.view);
						beginPass(encoder, reserveRows(layerWidth, layerHeight).view, true, 0, 0, 0, 0);
						encoder.renderSetPipeline(blurPass.pipeline);
						encoder.renderSetBindGroup(LayerBlurShader.FRAME_GROUP, inner.blurGroup);
						encoder.renderSetBindGroup(LayerBlurShader.TEXTURE_records_GROUP, blurPass.records);
						encoder.renderDrawRange(6, 1, 0, start);
						encoder.renderEnd();
					}
					depth--;
					beginPass(encoder, depth == 0 ? base : layers[depth - 1].view, false, 0, 0, 0, 0);
					if (shadowGroup == null) {
						// An opacity/mask-only layer still needs the declared binding, not a full-size shadow.
						if (shadow == null)
							reserveShadow(1, 1);
						var bindings = new GpuBindings();
						bindings.texture(shadow.view);
						bindings.sampler(glyphSampler);
						shadowGroup = device.bindGroup(layerPass.pipeline, LayerShader.TEXTURE_shadow_GROUP, bindings);
						bindings.destroy();
					}
					if (blurred && rowsGroup == null)
						rowsGroup = layerGroup(layerPass, LayerShader.FRAME_GROUP, rows.view);
					if (!blurred && inner.group == null)
						inner.group = layerGroup(layerPass, LayerShader.FRAME_GROUP, inner.view);
					encoder.renderSetPipeline(layerPass.pipeline);
					encoder.renderSetBindGroup(LayerShader.FRAME_GROUP, blurred ? rowsGroup : inner.group);
					encoder.renderSetBindGroup(LayerShader.TEXTURE_shadow_GROUP, shadowGroup);
					encoder.renderSetBindGroup(LayerShader.TEXTURE_records_GROUP, layerPass.records);
					encoder.renderDrawRange(6, 1, 0, start);
					start++;
					continue;
				}
				if (kind == DisplayList.PRIM_CANVAS) {
					paintCanvas(encoder, list, start, width, height, layerWidth, layerHeight, depth == 0 ? base : layers[depth - 1].view, region);
					start++;
					continue;
				}
				var end = start + 1;
				while (end < list.count && list.kind(end) == kind && (visible == null || visible[end]))
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
	}

	/**
		Hands the pass to the canvas of the record at `at`, scissored to its
		clipped box, then sets the scissor back to the whole target. Nothing
		else needs restoring: each run sets its own pipeline and bindings.
	**/
	function paintCanvas(encoder:GpuEncoder, list:DisplayList, at:Int, width:Int, height:Int, targetWidth:Int, targetHeight:Int, target:GpuTextureView,
			?region:Array<Int>):Void {
		var placed = canvasBox(list, at, width, height, targetWidth, targetHeight);
		if (placed == null)
			return;
		var x0 = placed.x0, y0 = placed.y0, x1 = placed.x1, y1 = placed.y1;
		// Inside the region, when only a part of the frame is drawn.
		if (region != null) {
			x0 = Std.int(Math.max(x0, region[0]));
			y0 = Std.int(Math.max(y0, region[1]));
			x1 = Std.int(Math.min(x1, region[0] + region[2]));
			y1 = Std.int(Math.min(y1, region[1] + region[3]));
		}
		if (x1 <= x0 || y1 <= y0)
			return;
		var ratio = targetWidth / width;
		encoder.renderSetScissorRect(x0, y0, x1 - x0, y1 - y0);
		placed.canvas.paintWith(new CanvasFrame(this, device, encoder, format, at, placed.w, placed.h, placed.transform, placed.transform.scale() * ratio, ratio,
			[x0, y0, x1 - x0, y1 - y0], target));
		if (region != null)
			encoder.renderSetScissorRect(region[0], region[1], region[2], region[3]);
		else
			encoder.renderSetScissorRect(0, 0, targetWidth, targetHeight);
	}

	/** The canvas of the record at `at`, where its content box lies on the target, its pixels cut by its clips, and the way its coordinates go to units; null where it draws nothing. **/
	function canvasBox(list:DisplayList, at:Int, width:Int, height:Int, targetWidth:Int, targetHeight:Int):Null<{
		canvas:ashui.ui.Canvas,
		x0:Int,
		y0:Int,
		x1:Int,
		y1:Int,
		w:Float,
		h:Float,
		transform:ashui.draw.Affine
	}> {
		var canvas = ashui.ui.Canvas.at(Std.int(list.get(at, GRADIENT_FIELD)));
		if (canvas == null)
			return null;
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
		var x0 = Std.int(Math.max(0, Math.floor(box[0] * ratio))),
			y0 = Std.int(Math.max(0, Math.floor(box[1] * ratio)));
		var x1 = Std.int(Math.min(targetWidth, Math.ceil(box[2] * ratio))),
			y1 = Std.int(Math.min(targetHeight, Math.ceil(box[3] * ratio)));
		if (x1 <= x0 || y1 <= y0)
			return null;
		return {
			canvas: canvas,
			x0: x0,
			y0: y0,
			x1: x1,
			y1: y1,
			w: w,
			h: h,
			transform: transform
		};
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
		return [
			Math.max(a[0], b[0]),
			Math.max(a[1], b[1]),
			Math.min(a[2], b[2]),
			Math.min(a[3], b[3])
		];

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
		for (g in [at.group, at.blurGroup, at.shadowPassGroup, at.backdropRowsGroup, at.blitGroup])
			if (g != null)
				g.destroy();
		at.view.destroy();
		at.texture.destroy();
	}

	function target(width:Int, height:Int):LayerTarget {
		var size = new GpuExtent3D(width);
		size.height(height);
		var texture = device.texture(new GpuTextureDescriptor(size, format, GpuFlags.TEXTURE_RENDER_ATTACHMENT | GpuFlags.TEXTURE_BINDING));
		return {
			texture: texture,
			view: texture.createView(new GpuTextureViewDescriptor()),
			width: width,
			height: height
		};
	}

	/** Content stays per depth; blur/shadow intermediates are shared and made only when used. **/
	function makeLayer(width:Int, height:Int):Layer {
		var content = target(width, height);
		return {
			texture: content.texture,
			view: content.view,
			group: null,
			blurGroup: null,
			shadowPassGroup: null,
			backdropRowsGroup: null,
			blitGroup: null,
			width: width,
			height: height
		};
	}

	function reserveRows(width:Int, height:Int):LayerTarget {
		if (rows == null || rows.width != width || rows.height != height) {
			if (rowsGroup != null)
				rowsGroup.destroy();
			if (backdropGroup != null)
				backdropGroup.destroy();
			if (liquidBackdropGroup != null)
				liquidBackdropGroup.destroy();
			rowsGroup = null;
			backdropGroup = null;
			liquidBackdropGroup = null;
			if (rows != null) {
				rows.view.destroy();
				rows.texture.destroy();
			}
			rows = target(width, height);
		}
		return rows;
	}

	function reserveShadow(width:Int, height:Int):LayerTarget {
		if (shadow == null || shadow.width != width || shadow.height != height) {
			if (shadowGroup != null)
				shadowGroup.destroy();
			shadowGroup = null;
			if (shadow != null) {
				shadow.view.destroy();
				shadow.texture.destroy();
			}
			shadow = target(width, height);
		}
		return shadow;
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

	/** Whether only the rows of the records texture that differ from what it holds are written, not all of them; `ASHUI_DIFF_UPLOAD=0` turns it off, for comparing. **/
	public var diffUpload = Sys.getEnv("ASHUI_DIFF_UPLOAD") != "0";

	/** What the records texture holds, as last written, and how many of its rows. **/
	var recordsSent:Null<haxe.io.Bytes> = null;

	var recordsSentRows = 0;

	/** Writes `rows` rows of `bytes` to the records texture: from the first row that differs from what it holds to the last. **/
	function sendRecords(queue:gpu.GpuQueue, bytes:haxe.io.Bytes, rows:Int):Void {
		var rowBytes = DisplayList.ROW_TEXELS * 16;
		var from = 0, to = rows;
		if (diffUpload && recordsSent != null && recordsSentRows > 0) {
			var now:hl.Bytes = bytes, was:hl.Bytes = recordsSent;
			var shared = rows < recordsSentRows ? rows : recordsSentRows;
			while (from < shared && now.compare(from * rowBytes, was, from * rowBytes, rowBytes) == 0)
				from++;
			if (from == rows) {
				recordsSentRows = rows;
				return;
			}
			// Rows past what it held are new; of the rest, the last that differs ends it.
			if (rows <= recordsSentRows)
				while (to > from && now.compare((to - 1) * rowBytes, was, (to - 1) * rowBytes, rowBytes) == 0)
					to--;
		}
		if (to - from == rows)
			queue.writeTexture(records, bytes, DisplayList.ROW_TEXELS, rows, rowBytes);
		else {
			var origin = new gpu.GpuOrigin3D();
			origin.y(from);
			var destination = new gpu.GpuTexelCopyTextureInfo(records);
			destination.origin(origin);
			var layout = new gpu.GpuTexelCopyBufferLayout();
			layout.offset(haxe.Int64.ofInt(from * rowBytes));
			layout.bytesPerRow(rowBytes);
			layout.rowsPerImage(to - from);
			var extent = new gpu.GpuExtent3D(DisplayList.ROW_TEXELS);
			extent.height(to - from);
			queue.writeTextureWith(destination, bytes, layout, extent);
		}
		if (diffUpload) {
			if (recordsSent == null || recordsSent.length < rows * rowBytes) {
				var bigger = haxe.io.Bytes.alloc(rows * rowBytes + (rows * rowBytes >> 1));
				if (recordsSent != null)
					bigger.blit(0, recordsSent, 0, recordsSent.length);
				recordsSent = bigger;
			}
			recordsSent.blit(from * rowBytes, bytes, from * rowBytes, (to - from) * rowBytes);
			recordsSentRows = rows;
		}
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
		// The new texture holds nothing yet.
		recordsSentRows = 0;
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

	/** Whether a GPU error in a frame throws, as a test wants, or is reported once and the frame goes on, as a window wants. **/
	public var strict = true;

	/** The frames that had a GPU error. **/
	public var failedFrames(default, null) = 0;

	final reported = new Map<String, Bool>();

	/** wgpu reports validation errors on the device, not by throwing. **/
	function failOnError(doing:String):Void {
		var error = device.takeError();
		if (error == null)
			return;
		if (strict)
			throw 'gpu error $doing: $error';
		// What the frame drew is not known to be whole, so the next is drawn whole.
		failedFrames++;
		frameValid = false;
		var key = doing + error;
		if (!reported.exists(key)) {
			reported.set(key, true);
			Sys.stderr().writeString('[ashui] gpu error $doing, the frame goes on: $error\n');
		}
	}
}

private typedef LayerTarget = {
	final texture:GpuTexture;
	final view:GpuTextureView;
	final width:Int;
	final height:Int;
}

private typedef Layer = {
	> LayerTarget,

	/** Bindings that read this layer's content; filter outputs use shared scratch targets. **/
	var group:Null<GpuBindGroup>;

	var blurGroup:Null<GpuBindGroup>;
	var shadowPassGroup:Null<GpuBindGroup>;
	var backdropRowsGroup:Null<GpuBindGroup>;
	var blitGroup:Null<GpuBindGroup>;
}

/** A pipeline and its bind groups: the frame uniforms, and the records texture for a shader that reads records. **/
typedef Pass = {
	final pipeline:GpuPipeline;
	var group:Null<GpuBindGroup>;

	/** The pass's own bind group of the records texture: an inferred layout is one pipeline's. **/
	var records:Null<GpuBindGroup>;
}

/** What of a frame to draw again: the rects `[x, y, width, height]` of target pixels, none for nothing, and for each which records touch it. **/
private typedef Damage = {
	final rects:Array<Array<Int>>;
	final visible:Array<Array<Bool>>;
}
