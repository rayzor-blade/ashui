package ashui.types;

import ashui.reactive.Signal;

/**
	A fixed-size grid of straight-alpha RGBA pixels that a program replaces
	as often as it likes, for a `<surface>` to draw: frames another
	process produced, an emulator's screen, a software renderer's output.

	Created once at its size. `write` replaces a rectangle and `writeAll` the
	whole of it; both only note what changed, and the renderer uploads the
	changed rectangle once per frame, whatever the number of writes. A
	surface nothing wrote to since it was drawn costs no upload.

	```haxe
	var screen = new PixelSurface(1280, 720);
	screen.writeAll(frameBytes);
	<surface source={screen} fit={Contain} />
	```
**/
class PixelSurface {
	public final width:Int;
	public final height:Int;

	/** Counts changes: each write adds one. A reader that kept the last one it drew knows whether anything is new. **/
	public var generation(default, null) = 0;

	/** `generation` as a signal: a `<surface>` asks for a frame when it changes. **/
	public final changed = Signal.make(0);

	/** The pixels, `width * 4` bytes a row. **/
	public final pixels:haxe.io.Bytes;

	final readers:Array<SurfaceReader> = [];
	final listeners:Array<Void->Void> = [];

	public function new(width:Int, height:Int) {
		if (width <= 0 || height <= 0)
			throw "A surface needs a positive size";
		this.width = width;
		this.height = height;
		pixels = haxe.io.Bytes.alloc(width * height * 4);
	}

	/**
		Replaces the `w` by `h` rectangle at `(x, y)` with `source`'s RGBA rows,
		`stride` bytes apart (`w * 4` when it is 0). The part of the rectangle
		outside the surface is left out.
	**/
	public function write(source:haxe.io.Bytes, x:Int, y:Int, w:Int, h:Int, stride = 0):Void {
		if (stride == 0)
			stride = w * 4;
		if (w <= 0 || h <= 0 || stride < w * 4 || source.length < (h - 1) * stride + w * 4)
			throw "The bytes do not hold the rectangle";
		var x0 = x < 0 ? 0 : x, y0 = y < 0 ? 0 : y;
		var x1 = x + w > width ? width : x + w, y1 = y + h > height ? height : y + h;
		if (x1 <= x0 || y1 <= y0)
			return;
		var row = (x1 - x0) * 4;
		for (r in y0...y1)
			pixels.blit((r * width + x0) * 4, source, (r - y) * stride + (x0 - x) * 4, row);
		touch(x0, y0, x1, y1);
	}

	/** Replaces every pixel with `source`, `width * height * 4` bytes. **/
	public function writeAll(source:haxe.io.Bytes):Void {
		if (source.length < pixels.length)
			throw "The bytes do not hold the surface";
		pixels.blit(0, source, 0, pixels.length);
		touch(0, 0, width, height);
	}

	/** Marks the rectangle as changed, for a program that wrote into `pixels` itself. **/
	public function touch(x0:Int, y0:Int, x1:Int, y1:Int):Void {
		for (r in readers)
			r.add(x0, y0, x1, y1);
		generation++;
		changed.set(generation);
		for (l in listeners.copy())
			l();
	}

	/** Calls `listener` after each change; returns what stops it. **/
	public function listen(listener:Void->Void):Void->Void {
		listeners.push(listener);
		return () -> listeners.remove(listener);
	}

	/** A reader of what changes from now on, starting with the whole surface: each renderer that draws it has its own. **/
	public function reader():SurfaceReader {
		var r = new SurfaceReader(this);
		r.add(0, 0, width, height);
		readers.push(r);
		return r;
	}

	@:allow(ashui.types.SurfaceReader)
	function forget(r:SurfaceReader):Void
		readers.remove(r);

	var snapshots:Array<Bitmap> = [];
	var snapshotOf = -1;

	/**
		The surface's pixels as a `Bitmap`, for what a bitmap can be: `Brush.bitmapPattern`, `Brush.bitmap` and a canvas's
		`image`. It is a copy, so a write to the surface is not in it; a call after a write makes a new one, which the draw
		that uses it should redo when `changed` does. Making one encodes and decodes the whole surface, so a surface
		written every frame is drawn with `ctx.surface` instead. The one before the last is freed here.
	**/
	public function bitmap():Bitmap {
		if (snapshotOf != generation || snapshots.length == 0) {
			snapshots.push(Bitmap.fromBytes(ashui.core.render.Png.encode(width, height, pixels)));
			snapshotOf = generation;
			if (snapshots.length > 2)
				snapshots.shift().dispose();
		}
		return snapshots[snapshots.length - 1];
	}
}

/** What changed in a `PixelSurface` since its reader last took it. **/
class SurfaceReader {
	public final surface:PixelSurface;

	var x0 = 0;
	var y0 = 0;
	var x1 = 0;
	var y1 = 0;
	var dirty = false;

	@:allow(ashui.types.PixelSurface)
	function new(surface:PixelSurface)
		this.surface = surface;

	@:allow(ashui.types.PixelSurface)
	function add(ax0:Int, ay0:Int, ax1:Int, ay1:Int):Void {
		if (dirty) {
			x0 = ax0 < x0 ? ax0 : x0;
			y0 = ay0 < y0 ? ay0 : y0;
			x1 = ax1 > x1 ? ax1 : x1;
			y1 = ay1 > y1 ? ay1 : y1;
		} else {
			dirty = true;
			x0 = ax0;
			y0 = ay0;
			x1 = ax1;
			y1 = ay1;
		}
	}

	/** Whether something changed that this reader has not taken. **/
	public function pending():Bool
		return dirty;

	/** The changed rectangle as x, y, width, height since the last call, or null when nothing changed. **/
	public function take():Null<Array<Int>> {
		if (!dirty)
			return null;
		dirty = false;
		return [x0, y0, x1 - x0, y1 - y0];
	}

	/** Makes the whole surface count as changed again, as a new GPU device needs. **/
	public function invalidate():Void
		add(0, 0, surface.width, surface.height);

	public function dispose():Void
		surface.forget(this);
}
