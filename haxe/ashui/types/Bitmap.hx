package ashui.types;

#if !macro
import ashui.core.externs.BitmapNative;
#end
#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
#end

/**
	A raster image, PNG, JPEG or WebP, decoded once and drawn by `ashui.ui.Image`
	or as a background with `Brush.bitmap`. Each place it is drawn resamples
	it to the size it covers on screen, so a large photo costs no more than
	the pixels it fills, and a zoom keeps it sharp up to its own resolution.

	```haxe
	var photo = Bitmap.embed("assets/photo.jpg");   // read at compile time
	var icon = Bitmap.load("icons/app.png");        // read when called
	```
**/
class Bitmap {
	/**
		Slots of image records from this up are bitmaps, `BASE + slot * 4 +
		fit`; records are 32-bit floats, exact to 2^24, which bounds them.
	**/
	@:noCompletion public static inline var BASE = 1 << 20;

	/** The image file at `path`, relative to the build's working directory, put in the program at compile time. **/
	public static macro function embed(path:String):Expr {
		var bytes = try sys.io.File.getBytes(path) catch (e:Dynamic) Context.error('bitmap: cannot read $path', Context.currentPos());
		var name = "ashui.bitmap:" + path;
		Context.addResource(name, bytes);
		return macro ashui.types.Bitmap.fromResource($v{name});
	}

	// What follows runs in the program, not in the compiler.
	#if !macro

	static final loaded = new Map<String, Bitmap>();

	/** Names the decoded image to the renderer. **/
	public final slot:Int;

	/** Its size in pixels. **/
	public var width(default, null):Int;

	public var height(default, null):Int;

	/**
		Frees its decoded pixels once a mesh's texture is made of them, keeping
		only the GPU's copy: for an image drawn only on meshes, as glTF's are.
		After that it draws nothing anywhere else.
	**/
	public var gpuOnly = false;

	/**
		Whether a mesh texture made from this bitmap may be block-compressed
		(BC), which uses a quarter of the memory. Set it to false to keep the
		texture exact, for images whose fine points compression would smear,
		such as a sky's stars.
	**/
	public var compressible = true;

	/** Called with each bitmap as it is disposed: what holds a copy of its pixels lets it go. **/
	@:noCompletion public static final disposing:Array<Bitmap->Void> = [];

	function new(slot:Int) {
		this.slot = slot;
		width = BitmapNative.blinc_bitmap_size(slot, false);
		height = BitmapNative.blinc_bitmap_size(slot, true);
	}

	/** `bytes` of PNG, JPEG or WebP decoded; throws when they are not one. **/
	public static function fromBytes(bytes:haxe.io.Bytes):Bitmap {
		var slot = BitmapNative.blinc_bitmap_decode(bytes, bytes.length);
		if (slot < 0)
			throw "not a PNG, JPEG or WebP image";
		return new Bitmap(slot);
	}

	#if sys
	/** The image file at `path`, read once: loading the same path again gives the same bitmap. **/
	public static function load(path:String):Bitmap {
		var known = loaded.get(path);
		if (known != null)
			return known;
		var made = fromBytes(sys.io.File.getBytes(path));
		loaded.set(path, made);
		return made;
	}
	#end

	@:noCompletion public static function fromResource(name:String):Bitmap {
		var known = loaded.get(name);
		if (known != null)
			return known;
		var made = fromBytes(haxe.Resource.getBytes(name));
		loaded.set(name, made);
		return made;
	}

	/**
		Returns the bitmap's pixels resampled to `width` × `height`, row by
		row, four bytes each (red, green, blue, alpha). Use it to read an image
		as data, such as a height map. Returns null once a `gpuOnly` bitmap's
		pixels have been freed.
	**/
	public function pixels(width:Int, height:Int):Null<haxe.io.Bytes> {
		var out = haxe.io.Bytes.alloc(width * height * 4);
		return BitmapNative.blinc_bitmap_resample(slot, width, height, (Fill : Brush.ImageFit), out) ? out : null;
	}

	/**
		Shrinks it so that neither side is over `maxSide` pixels, keeping its
		shape, each side rounded to a multiple of 4 so a mesh texture made of
		it can be block-compressed. Its full-size pixels are freed at once.
		Call it before it is drawn. False when it was small enough already.
	**/
	public function shrink(maxSide:Int):Bool {
		if (!BitmapNative.blinc_bitmap_shrink(slot, maxSide))
			return false;
		width = BitmapNative.blinc_bitmap_size(slot, false);
		height = BitmapNative.blinc_bitmap_size(slot, true);
		return true;
	}

	/** Frees its pixels; it must not be drawn after. **/
	public function dispose():Void {
		for (f in disposing)
			f(this);
		BitmapNative.blinc_bitmap_release(slot);
		for (k => v in loaded)
			if (v == this)
				loaded.remove(k);
	}

	/** The image record slot that draws it fitted by `fit`. **/
	@:noCompletion public function slotFor(fit:Brush.ImageFit):Int
		return BASE + slot * 4 + (fit : Int);
	#end
}
