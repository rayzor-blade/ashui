package ashui.core.render;

import ashui.layout.DisplayList;
import ashui.layout.Element;
import ashui.layout.LayoutTree;
import ashui.layout.Node;
import ashui.reactive.Owner;
import gpu.BufferUsage;
import gpu.GpuBufferDescriptor;
import gpu.GpuDevice;
import gpu.GpuExtent3D;
import gpu.GpuInstance;
import gpu.GpuTextureDescriptor;
import gpu.GpuTextureViewDescriptor;
import gpu.Power;
import gpu.TextureFormat;
import gpu.TextureUsage;

/**
	Renders a tree offscreen to a PNG, for looking at what a UI draws without
	a window. Each snapshot is written to `dir()` as `<name>.png` and announced
	by a line appended to `dir()/events.log`, so a watcher tailing that file
	sees every one:

		snapshot <name> <absolute path> <width>x<height> <primitives> primitives
		error <name> <message>

	`dir()` is `$ASHUI_SNAPSHOT_DIR`, or `snapshots` under the working
	directory. tools/snapshot renders scene files this way.
**/
class Snapshot {
	static var device:Null<GpuDevice>;
	static var renderer:Null<Renderer>;

	public static function dir():String {
		var dir = Sys.getEnv("ASHUI_SNAPSHOT_DIR");
		return dir != null && dir != "" ? dir : "snapshots";
	}

	/**
		Builds a UI with `build` under a new owner and tree, lays it out at
		`width` × `height` and captures it as `name`. An exception is logged
		as an error event, then rethrown.
	**/
	public static function scene(name:String, width:Int, height:Int, build:Void->Element, clear = 0xffffff, clearAlpha = 1.0):String {
		try {
			var tree = new LayoutTree();
			var root:Element = Owner.root(tree, _ -> build());
			tree.flush();
			tree.computeLayout(root.node, width, height);
			return capture(name, tree, root.node, width, height, clear, clearAlpha);
		} catch (e:haxe.Exception) {
			event('error $name ${e.message.split("\n").join(" ")}');
			throw e;
		}
	}

	/**
		Draws `root` of `tree`, already laid out, into a `width` × `height`
		image cleared to `clear`, and writes it as `name`. Returns the PNG's
		path.
	**/
	public static function capture(name:String, tree:LayoutTree, root:Node, width:Int, height:Int, clear = 0xffffff, clearAlpha = 1.0):String {
		var list = new DisplayList();
		list.update(tree, root);
		var pixels = render(list, width, height, clear, clearAlpha);

		sys.FileSystem.createDirectory(dir());
		var path = sys.FileSystem.absolutePath(haxe.io.Path.join([dir(), '$name.png']));
		sys.io.File.saveBytes(path, Png.encode(width, height, pixels.bytes, pixels.stride));
		event('snapshot $name $path ${width}x$height ${list.count} primitives');
		return path;
	}

	/** RGBA rows of `list` drawn at `width` × `height`, `stride` bytes apart. **/
	static function render(list:DisplayList, width:Int, height:Int, clear:Int, clearAlpha:Float):{bytes:haxe.io.Bytes, stride:Int} {
		if (device == null) {
			var adapter = settle(new GpuInstance().requestAdapter(Power.HighPerformance));
			device = settle(adapter.requestDevice());
			renderer = new Renderer(device, TextureFormat.Rgba8unorm);
		}
		var size = new GpuExtent3D(width);
		size.height(height);
		var target = device.texture(new GpuTextureDescriptor(size, TextureFormat.Rgba8unorm, TextureUsage.RENDER_ATTACHMENT | TextureUsage.COPY_SRC));
		var view = target.createView(new GpuTextureViewDescriptor());
		renderer.draw(list, view, width, height, (clear >> 16 & 0xff) / 255, (clear >> 8 & 0xff) / 255, (clear & 0xff) / 255, clearAlpha);

		// Buffer copies take rows a multiple of 256 bytes apart.
		var stride = (width * 4 + 255) & ~255;
		var readback = device.createBuffer(new GpuBufferDescriptor(stride * height, BufferUsage.MAP_READ | BufferUsage.COPY_DST));
		var encoder = device.encoder();
		encoder.copyTextureToBuffer(target, readback, width, height, stride);
		encoder.submit(device.queue());
		settle(device.mapBuffer(readback, 0, stride * height));
		var bytes = haxe.io.Bytes.alloc(stride * height);
		readback.copyOut(0, bytes, bytes.length);
		readback.unmap();
		readback.destroy();
		target.destroy();
		var error = device.takeError();
		if (error != null)
			throw 'gpu error capturing: $error';
		return {bytes: bytes, stride: stride};
	}

	/**
		The value of `future`. Polls `isReady` instead of parking in `await`,
		which on Ash does not yet wake for futures hlwgpu settles (ash 158658d).
	**/
	static function settle<T>(future:ash.Future<T>):T {
		while (!future.isReady())
			Sys.sleep(0.001);
		return future.await();
	}

	static function event(line:String):Void {
		sys.FileSystem.createDirectory(dir());
		var out = sys.io.File.append(haxe.io.Path.join([dir(), "events.log"]), false);
		out.writeString(line + "\n");
		out.close();
	}
}
