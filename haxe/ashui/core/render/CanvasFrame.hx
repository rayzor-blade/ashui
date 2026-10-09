package ashui.core.render;

import ashui.core.render.Renderer.Pass;
import ashui.draw.Affine;
import gpu.GpuDevice;
import gpu.GpuEncoder;
import gpu.TextureFormat;

/**
	A canvas's turn in a frame: the render pass at the canvas's place in
	paint order, handed over to draw into with the GPU directly.

	The pass is begun and drawing into the frame's target, or the layer the
	canvas is in; its scissor is set to the canvas's clipped box, so any draw
	is clipped to it. For exact clipping, rounded clips, a clip-path, edge
	fades and opacity, a shader implements `UiShader`, is drawn with `draw`
	(or bound with `bind`), which draws it with the canvas's record as its
	instance, and multiplies its colour's alpha by `canvasClip(pixel)`,
	where `pixel` is the screen position `transform` gives:
	`paint={frame -> frame.draw(MyShader.WGSL, 6)}`.

	It is good only during the canvas's `paint`: the renderer restores its
	own state after.
**/
class CanvasFrame {
	public final device:GpuDevice;
	public final encoder:GpuEncoder;
	public final format:TextureFormat;

	/** The canvas's record in the display list. **/
	public final record:Int;

	/** The canvas's content box, in its own layout units. **/
	public final width:Float;

	public final height:Float;

	/** From the canvas's own coordinates, its content box's top-left at the origin, to the frame's layout units. **/
	public final transform:Affine;

	/** Target pixels to a unit of the canvas's own coordinates: what a tolerance or a hairline is worth. **/
	public final scale:Float;

	/** Target pixels to a unit of the frame's layout units, as the viewport `pixelToClip` takes is in layout units. **/
	public final pixelRatio:Float;

	/** The scissor set, in target pixels. **/
	public final scissorX:Int;

	public final scissorY:Int;
	public final scissorWidth:Int;
	public final scissorHeight:Int;

	final renderer:Renderer;

	/** The view the pass draws into, to begin it again after `suspend`. **/
	final target:gpu.GpuTextureView;

	@:allow(ashui.core.render.Renderer)
	function new(renderer:Renderer, device:GpuDevice, encoder:GpuEncoder, format:TextureFormat, record:Int, width:Float, height:Float,
			transform:Affine, scale:Float, pixelRatio:Float, scissor:Array<Int>, target:gpu.GpuTextureView) {
		this.renderer = renderer;
		this.target = target;
		this.device = device;
		this.encoder = encoder;
		this.format = format;
		this.record = record;
		this.width = width;
		this.height = height;
		this.transform = transform;
		this.scale = scale;
		this.pixelRatio = pixelRatio;
		scissorX = scissor[0];
		scissorY = scissor[1];
		scissorWidth = scissor[2];
		scissorHeight = scissor[3];
	}

	/**
		Ends the pass to run `passes`, which begin and end passes of their own
		on `encoder`, into textures of their own, then begins it again on the
		frame's target, keeping what it holds, scissored as before. What was
		set on the pass, pipelines and bindings, is gone after: set it again.
	**/
	public function suspend(passes:GpuEncoder->Void):Void {
		encoder.renderEnd();
		passes(encoder);
		@:privateAccess renderer.beginPass(encoder, target, false, 0, 0, 0, 0);
		encoder.renderSetScissorRect(scissorX, scissorY, scissorWidth, scissorHeight);
	}

	/** The renderer's image atlas, which images a canvas draws are resampled into. **/
	public var images(get, never):ImageAtlas;

	inline function get_images():ImageAtlas
		return @:privateAccess renderer.ensureImageAtlas();

	/** The sampler images are drawn through: linear between texels. **/
	public var imageSampler(get, never):gpu.GpuSampler;

	inline function get_imageSampler():gpu.GpuSampler
		return @:privateAccess renderer.glyphSampler;

	/**
		Draws `vertices` vertices of a `UiShader`, by its WGSL, once, as the
		canvas's record's instance: its `recordIndex`, and so `primitive` and
		`canvasClip`, are the canvas's. Its pipeline, alpha-blended into the
		frame's targets, is made the first time and kept.
	**/
	public function draw(wgsl:String, vertices:Int):Void {
		bind(wgsl);
		encoder.renderDrawRange(vertices, 1, 0, record);
	}

	/**
		Sets the pipeline of a `UiShader`, by its WGSL, with ashui's frame
		uniforms and records bound, and returns it: for a shader with bind
		groups of its own, set after this, its draws made on `encoder` with
		`record` as the first instance.
	**/
	public function bind(wgsl:String):Pass {
		var pipeline = renderer.uiPass(wgsl);
		encoder.renderSetPipeline(pipeline.pipeline);
		encoder.renderSetBindGroup(BoxShader.FRAME_GROUP, pipeline.group);
		encoder.renderSetBindGroup(BoxShader.TEXTURE_records_GROUP, pipeline.records);
		return pipeline;
	}
}
