package ashui.core.render;

import ashui.layout.Element;
import ashui.layout.LayoutTree;
import ashui.layout.Node;
import ashui.reactive.Owner;
import gpu.GpuTextureViewDescriptor;

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
	static var offscreen:Null<Offscreen>;

	/** Where snapshots go: `$ASHUI_SNAPSHOT_DIR`, or `snapshots` under the working directory. **/
	public static function dir():String {
		var dir = Sys.getEnv("ASHUI_SNAPSHOT_DIR");
		return dir != null && dir != "" ? dir : "snapshots";
	}

	/**
		Builds a UI with `build` under a new owner and tree, lays it out at
		`width` × `height` and captures it as `name`, `scale` image pixels per
		layout unit. An exception is logged as an error event, then rethrown.
	**/
	public static function scene(name:String, width:Int, height:Int, build:Void->Element, clear = 0xffffff, clearAlpha = 1.0, scale = 1.0):String {
		try {
			var tree = new LayoutTree();
			var root:Element = Owner.root(tree, _ -> build());
			tree.flush();
			tree.computeLayout(root.node, width, height);
			return capture(name, tree, root.node, width, height, clear, clearAlpha, scale);
		} catch (e:haxe.Exception) {
			event('error $name ${e.message.split("\n").join(" ")}');
			throw e;
		}
	}

	/**
		Draws `root` of `tree`, laid out at `width` × `height`, into an image
		`scale` times that size cleared to `clear`, and writes it as `name`.
		Returns the PNG's path.
	**/
	public static function capture(name:String, tree:LayoutTree, root:Node, width:Int, height:Int, clear = 0xffffff, clearAlpha = 1.0,
			scale = 1.0):String {
		if (offscreen == null)
			offscreen = Offscreen.create();
		offscreen.clear = clear;
		offscreen.clearAlpha = clearAlpha;
		offscreen.scale = scale;
		var pixelWidth = Math.round(width * scale);
		var pixelHeight = Math.round(height * scale);
		var texture = offscreen.createTexture(pixelWidth, pixelHeight);
		offscreen.renderTree(tree, root, texture.createView(new GpuTextureViewDescriptor()), width, height);
		var pixels = offscreen.readRgba8(texture, pixelWidth, pixelHeight);
		texture.destroy();
		width = pixelWidth;
		height = pixelHeight;

		sys.FileSystem.createDirectory(dir());
		var path = sys.FileSystem.absolutePath(haxe.io.Path.join([dir(), '$name.png']));
		sys.io.File.saveBytes(path, Png.encode(width, height, pixels));
		event('snapshot $name $path ${width}x$height ${offscreen.primitives} primitives');
		return path;
	}

	static function event(line:String):Void {
		sys.FileSystem.createDirectory(dir());
		var out = sys.io.File.append(haxe.io.Path.join([dir(), "events.log"]), false);
		out.writeString(line + "\n");
		out.close();
	}
}
