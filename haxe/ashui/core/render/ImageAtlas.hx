package ashui.core.render;

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
	An RGBA texture that rasterized images are packed into, so every image
	on screen is drawn from one texture. Images are placed on shelves, rows
	as tall as their tallest image, with a transparent pixel between them so
	filtering at one image's edge reads nothing of its neighbour. Each image
	is uploaded on its own when it is added. A full atlas doubles, copying
	what it holds, up to `MAX_SIZE`; past that `reset` empties it.
**/
class ImageAtlas {
	public static inline var MAX_SIZE = 4096;
	static inline var GAP = 1;

	final device:GpuDevice;
	final entries = new Map<String, Rect>();
	var texture:GpuTexture;
	var size:Int;
	var shelves:Array<{y:Int, height:Int, x:Int}> = [];
	var nextY = 0;

	/** The texture's view; replaced, with `revision` bumped, when the atlas grows. **/
	public var view(default, null):GpuTextureView;

	/** Counts the views `view` has had, so bind groups holding an old one are rebuilt. **/
	public var revision(default, null) = 0;

	/** An empty atlas on `device`, `size` pixels square until it grows. **/
	public function new(device:GpuDevice, size = 1024) {
		this.device = device;
		this.size = size;
		allocate();
	}

	/**
		The rect of the image `key`, `width` × `height` pixels, in the atlas.
		On first sight `rasterize` fills its pixels, straight-alpha RGBA, and
		it is uploaded. Null when `rasterize` fails or the atlas is full.
	**/
	public function get(key:String, width:Int, height:Int, rasterize:haxe.io.Bytes->Bool):Null<Rect> {
		var known = entries.get(key);
		if (known != null)
			return known;
		var spot = place(width, height);
		if (spot == null)
			return null;
		var pixels = haxe.io.Bytes.alloc(width * height * 4);
		if (!rasterize(pixels))
			return null;
		upload(pixels, spot.x, spot.y, width, height);
		var rect = new Rect(spot.x, spot.y, width, height);
		entries.set(key, rect);
		return rect;
	}

	/** Forgets every image; the texture is reused. **/
	public function reset():Void {
		entries.clear();
		shelves = [];
		nextY = 0;
	}

	function place(width:Int, height:Int):Null<{x:Int, y:Int}> {
		if (width + GAP > MAX_SIZE || height + GAP > MAX_SIZE)
			return null;
		while (true) {
			for (shelf in shelves)
				if (height <= shelf.height && shelf.x + width + GAP <= size) {
					var spot = {x: shelf.x, y: shelf.y};
					shelf.x += width + GAP;
					return spot;
				}
			if (nextY + height + GAP <= size && width + GAP <= size) {
				shelves.push({y: nextY, height: height, x: width + GAP});
				var spot = {x: 0, y: nextY};
				nextY += height + GAP;
				return spot;
			}
			if (size >= MAX_SIZE)
				return null;
			grow();
		}
	}

	/** Doubles the texture, keeping what it holds where it is. **/
	function grow():Void {
		var old = texture;
		var oldSize = size;
		size *= 2;
		allocate();
		var encoder = device.encoder();
		encoder.copyTextureToTexture(old, texture, oldSize, oldSize);
		encoder.submit(device.queue());
		old.destroy();
	}

	function allocate():Void {
		if (revision > 0)
			view.destroy();
		var extent = new GpuExtent3D(size);
		extent.height(size);
		texture = device.texture(new GpuTextureDescriptor(extent, TextureFormat.Rgba8unorm,
			GpuFlags.TEXTURE_BINDING | GpuFlags.TEXTURE_COPY_DST | GpuFlags.TEXTURE_COPY_SRC));
		view = texture.createView(new GpuTextureViewDescriptor());
		revision++;
	}

	function upload(pixels:haxe.io.Bytes, x:Int, y:Int, width:Int, height:Int):Void {
		var origin = new GpuOrigin3D();
		origin.x(x);
		origin.y(y);
		var destination = new GpuTexelCopyTextureInfo(texture);
		destination.origin(origin);
		var layout = new GpuTexelCopyBufferLayout();
		layout.bytesPerRow(width * 4);
		layout.rowsPerImage(height);
		var extent = new GpuExtent3D(width);
		extent.height(height);
		device.queue().writeTextureWith(destination, pixels, layout, extent);
	}
}

/** Where an image sits in its atlas, in pixels. **/
class Rect {
	public final x:Int;
	public final y:Int;
	public final width:Int;
	public final height:Int;

	public function new(x:Int, y:Int, width:Int, height:Int) {
		this.x = x;
		this.y = y;
		this.width = width;
		this.height = height;
	}
}
