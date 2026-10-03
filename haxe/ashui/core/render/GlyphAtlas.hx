package ashui.core.render;

import ashui.core.externs.TextNative;
import gpu.GpuDevice;
import gpu.GpuExtent3D;
import gpu.GpuTexture;
import gpu.GpuTextureDescriptor;
import gpu.GpuTextureView;
import gpu.GpuTextureViewDescriptor;
import gpu.TextureFormat;
import gpu.TextureUsage;

/**
	The GPU copy of one of the text engine's glyph atlases. The engine packs
	each glyph it rasterizes into the atlas; `sync` uploads the atlas when it
	changed since this copy last took it, replacing the texture when the
	atlas grew. Every renderer keeps its own copies of the one engine's.
**/
class GlyphAtlas {
	final device:GpuDevice;
	final color:Bool;
	final bytesPerPixel:Int;
	final info = haxe.io.Bytes.alloc(12);
	var seen = 0;
	var pixels:haxe.io.Bytes = haxe.io.Bytes.alloc(0);
	var texture:Null<GpuTexture> = null;

	/** The texture's view; replaced, with `revision` bumped, when the atlas grows. **/
	public var view(default, null):GpuTextureView;

	/** Counts the views `view` has had, so bind groups holding an old one are rebuilt. **/
	public var revision(default, null) = 0;

	/** The coverage atlas, or the colour-glyph atlas when `color`. **/
	public function new(device:GpuDevice, color:Bool) {
		this.device = device;
		this.color = color;
		bytesPerPixel = color ? 4 : 1;
		allocate(1, 1);
	}

	/** Uploads the atlas if it changed since the last call. **/
	public function sync():Void {
		var which = color ? 1 : 0;
		var size = TextNative.blinc_text_atlas_take(which, seen, pixels.getData(), pixels.length, info.getData());
		if (size == 0)
			return;
		if (size > pixels.length) {
			pixels = haxe.io.Bytes.alloc(size);
			size = TextNative.blinc_text_atlas_take(which, seen, pixels.getData(), pixels.length, info.getData());
			if (size == 0)
				return;
		}
		var width = info.getInt32(0);
		var height = info.getInt32(4);
		seen = info.getInt32(8);
		if (width <= 0 || height <= 0 || width * height * bytesPerPixel > size)
			return;
		if (texture == null || texture.width() != width || texture.height() != height)
			allocate(width, height);
		device.queue().writeTexture(texture, pixels, width, height, width * bytesPerPixel);
	}

	function allocate(width:Int, height:Int):Void {
		if (texture != null)
			texture.destroy();
		var size = new GpuExtent3D(width);
		size.height(height);
		texture = device.texture(new GpuTextureDescriptor(size, color ? TextureFormat.Rgba8unorm : TextureFormat.R8unorm,
			GpuFlags.TEXTURE_BINDING | GpuFlags.TEXTURE_COPY_DST));
		view = texture.createView(new GpuTextureViewDescriptor());
		revision++;
	}
}
