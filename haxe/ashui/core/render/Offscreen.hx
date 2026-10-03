package ashui.core.render;

import ashui.layout.DisplayList;
import ashui.layout.Element;
import ashui.layout.LayoutTree;
import ashui.layout.Node;
import gpu.BufferUsage;
import gpu.GpuBufferDescriptor;
import gpu.GpuDevice;
import gpu.GpuExtent3D;
import gpu.GpuInstance;
import gpu.GpuTexture;
import gpu.GpuTextureDescriptor;
import gpu.GpuTextureView;
import gpu.GpuTextureViewDescriptor;
import gpu.Power;
import gpu.TextureFormat;
import gpu.TextureUsage;

/**
	Draws a UI into GPU textures without a window, as Blinc's `BlincApp`
	does: into a view the caller owns, into a fresh texture the caller can
	sample or copy in its own passes, or back to RGBA bytes.

	It renders on the caller's device when given one, so a host engine can
	put the UI in its own textures; `create` makes a device of its own.
	Textures are in `format`; pick a non-sRGB one, as Blinc does.
**/
class Offscreen {
	public final device:GpuDevice;
	public final format:TextureFormat;

	/** What each frame is cleared to before drawing: `clear` is RGB, `clearAlpha` 0 to 1. **/
	public var clear = 0x000000;
	public var clearAlpha = 0.0;

	/**
		Device pixels per layout unit: the target's size over the size the UI
		is laid out at. Text is rasterized for it, so it is sharp on a dense
		display.
	**/
	public var scale = 1.0;

	/** The target texture's size in pixels, when it is not the size drawn at times `scale` rounded: a window's surface. **/
	public var targetWidth:Null<Int> = null;
	public var targetHeight:Null<Int> = null;

	/** Seconds the last `render` spent flushing, laying out, building the display list and encoding the draw. **/
	public var timings(default, null) = {flush: 0.0, layout: 0.0, list: 0.0, draw: 0.0};

	/** How many primitives the last frame drew. **/
	public var primitives(get, never):Int;

	final renderer:Renderer;
	final list = new DisplayList();

	inline function get_primitives():Int
		return list.count;

	public function new(device:GpuDevice, format:TextureFormat = Rgba8unorm) {
		this.device = device;
		this.format = format;
		renderer = new Renderer(device, format);
	}

	/** An offscreen renderer on a device of its own. **/
	public static function create(format:TextureFormat = Rgba8unorm):Offscreen {
		var adapter = new GpuInstance().requestAdapter(Power.HighPerformance).await();
		return new Offscreen(adapter.requestDevice().await(), format);
	}

	/**
		Applies `root`'s pending changes, lays it out at `width` × `height`
		and draws it into `view`, a view of a texture in `format`.
	**/
	public function render(root:Element, view:GpuTextureView, width:Int, height:Int):Void {
		var t0 = haxe.Timer.stamp();
		root.tree.flush();
		var t1 = haxe.Timer.stamp();
		root.tree.computeLayout(root.node, width, height);
		var t2 = haxe.Timer.stamp();
		renderTree(root.tree, root.node, view, width, height);
		timings.flush = t1 - t0;
		timings.layout = t2 - t1;
	}

	/** Draws `root` of `tree`, already laid out, into `view`. **/
	public function renderTree(tree:LayoutTree, root:Node, view:GpuTextureView, width:Int, height:Int):Void {
		var t0 = haxe.Timer.stamp();
		list.update(tree, root, scale);
		var t1 = haxe.Timer.stamp();
		timings.list = t1 - t0;
		var pixelWidth = targetWidth != null ? targetWidth : Math.round(width * scale);
		var pixelHeight = targetHeight != null ? targetHeight : Math.round(height * scale);
		renderer.draw(list, view, width, height, (clear >> 16 & 0xff) / 255, (clear >> 8 & 0xff) / 255, (clear & 0xff) / 255, clearAlpha,
			pixelWidth, pixelHeight);
		timings.draw = haxe.Timer.stamp() - t1;
	}

	/**
		`root` drawn as by `render` into a new texture in `format`, which the
		caller owns and destroys. It can be a render target again, sampled,
		or copied from.
	**/
	public function renderToTexture(root:Element, width:Int, height:Int):GpuTexture {
		var texture = createTexture(width, height);
		var view = texture.createView(new GpuTextureViewDescriptor());
		render(root, view, width, height);
		return texture;
	}

	/** `root` drawn as by `render`, read back as `width * height * 4` RGBA bytes. **/
	public function renderToRgba8(root:Element, width:Int, height:Int):haxe.io.Bytes {
		var texture = renderToTexture(root, width, height);
		var pixels = readRgba8(texture, width, height);
		texture.destroy();
		return pixels;
	}

	/** A texture in `format` of `width` × `height` that can be drawn to, sampled and copied. **/
	public function createTexture(width:Int, height:Int):GpuTexture {
		var size = new GpuExtent3D(width);
		size.height(height);
		return device.texture(new GpuTextureDescriptor(size, format,
			TextureUsage.RENDER_ATTACHMENT | TextureUsage.TEXTURE_BINDING | TextureUsage.COPY_SRC));
	}

	/**
		The pixels of `texture`, a texture in `format` with `COPY_SRC`, as
		`width * height * 4` bytes in R, G, B, A order whatever the format's
		own order, rows packed.
	**/
	public function readRgba8(texture:GpuTexture, width:Int, height:Int):haxe.io.Bytes {
		// Buffer copies take rows a multiple of 256 bytes apart.
		var stride = (width * 4 + 255) & ~255;
		var readback = device.createBuffer(new GpuBufferDescriptor(stride * height, BufferUsage.MAP_READ | BufferUsage.COPY_DST));
		var encoder = device.encoder();
		encoder.copyTextureToBuffer(texture, readback, width, height, stride);
		encoder.submit(device.queue());
		device.mapBuffer(readback, 0, stride * height).await();
		var padded = haxe.io.Bytes.alloc(stride * height);
		readback.copyOut(0, padded, padded.length);
		readback.unmap();
		readback.destroy();
		var error = device.takeError();
		if (error != null)
			throw 'gpu error reading a texture back: $error';

		var row = width * 4;
		var out = haxe.io.Bytes.alloc(row * height);
		for (y in 0...height)
			out.blit(y * row, padded, y * stride, row);
		if (format == Bgra8unorm || format == Bgra8unormSrgb) {
			var i = 0;
			while (i < out.length) {
				var b = out.get(i);
				out.set(i, out.get(i + 2));
				out.set(i + 2, b);
				i += 4;
			}
		}
		return out;
	}
}
