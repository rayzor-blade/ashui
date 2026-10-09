package ashui.core.render;

import ashui.core.externs.TextNative;
import gpu.GpuDevice;
import gpu.GpuExtent3D;
import gpu.GpuOrigin3D;
import gpu.GpuTexelCopyBufferLayout;
import gpu.GpuTexelCopyTextureInfo;
import gpu.GpuTexture;
import gpu.GpuTextureDescriptor;
import gpu.GpuTextureView;
import gpu.GpuTextureViewDescriptor;
import gpu.TextureFormat;
import gpu.TextureUsage;

/**
	The GPU copy of one of the text engine's glyph atlases. The engine packs
	each glyph it rasterizes into the atlas; `sync` uploads the region that
	changed since this copy last took it, or the whole atlas when it grew,
	replacing the texture then. Every renderer keeps its own copies of the
	one engine's.
**/
class GlyphAtlas {
	final device:GpuDevice;
	final color:Bool;
	final bytesPerPixel:Int;
	final info = haxe.io.Bytes.alloc(28);
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

	/** Uploads what of the atlas changed since the last call. **/
	public function sync():Void {
		var which = color ? 1 : 0;
		if (!take(which, seen))
			return;
		var width = info.getInt32(0), height = info.getInt32(4);
		if (width <= 0 || height <= 0)
			return;
		if (texture == null || texture.width() != width || texture.height() != height) {
			allocate(width, height);
			// A new texture takes the whole atlas, whatever changed of it.
			if (info.getInt32(20) != width || info.getInt32(24) != height)
				if (!take(which, 0))
					return;
		}
		seen = info.getInt32(8);
		var x = info.getInt32(12), y = info.getInt32(16), w = info.getInt32(20), h = info.getInt32(24);
		if (w <= 0 || h <= 0)
			return;
		var origin = new GpuOrigin3D();
		origin.x(x);
		origin.y(y);
		var destination = new GpuTexelCopyTextureInfo(texture);
		destination.origin(origin);
		var layout = new GpuTexelCopyBufferLayout();
		layout.bytesPerRow(w * bytesPerPixel);
		layout.rowsPerImage(h);
		var extent = new GpuExtent3D(w);
		extent.height(h);
		device.queue().writeTextureWith(destination, pixels, layout, extent);
	}

	/** The region changed since revision `since` into `pixels`, its place in `info`; false when there is none. **/
	function take(which:Int, since:Int):Bool {
		var size = TextNative.blinc_text_atlas_take(which, since, pixels.getData(), pixels.length, info.getData());
		if (size == 0)
			return false;
		if (size > pixels.length) {
			// Room for this region and some to spare, so a few larger ones do not each allocate.
			pixels = haxe.io.Bytes.alloc(size + (size >> 1));
			size = TextNative.blinc_text_atlas_take(which, since, pixels.getData(), pixels.length, info.getData());
		}
		return size > 0;
	}

	function allocate(width:Int, height:Int):Void {
		if (texture != null) {
			view.destroy();
			texture.destroy();
		}
		var size = new GpuExtent3D(width);
		size.height(height);
		texture = device.texture(new GpuTextureDescriptor(size, color ? TextureFormat.Rgba8unorm : TextureFormat.R8unorm,
			GpuFlags.TEXTURE_BINDING | GpuFlags.TEXTURE_COPY_DST));
		view = texture.createView(new GpuTextureViewDescriptor());
		revision++;
	}
}
