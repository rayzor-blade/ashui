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

	static var ids = 0;
	static var nextGeneration = 0;
	static final generations = new Map<Int, Int>();

	/** Distinguishes a native slot's successive occupants in renderer caches. **/
	@:noCompletion public static function generation(slot:Int):Int
		return generations.get(slot);

	/** Names it from the moment it is made, which `slot` does not for a bitmap whose decoding waits. **/
	public final id:Int;

	/** Names the decoded image to the renderer; reading it decodes a bitmap made `deferred`. **/
	public var slot(get, never):Int;

	var made:Int;
	var encoded:Null<haxe.io.Bytes> = null;
	var shrinkTo = 0;
	var pinned = false;
	var disposed = false;
	var compressedForms:Null<Map<Int, ashui.draw3d.BcImage>> = null;

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
		id = ids++;
		made = slot;
		if (slot >= 0) {
			generations.set(slot, nextGeneration++);
			width = BitmapNative.blinc_bitmap_size(slot, false);
			height = BitmapNative.blinc_bitmap_size(slot, true);
		}
	}

	function get_slot():Int {
		pinned = true;
		return decode();
	}

	function decode():Int {
		if (disposed) throw "bitmap pixels have been disposed";
		if (made < 0) {
			if (encoded == null) throw "bitmap pixels have been freed";
			made = BitmapNative.blinc_bitmap_decode(encoded, encoded.length);
			if (made < 0)
				throw "not a PNG, JPEG or WebP image";
			generations.set(made, nextGeneration++);
			if (shrinkTo > 0)
				BitmapNative.blinc_bitmap_shrink(made, shrinkTo);
			width = BitmapNative.blinc_bitmap_size(made, false);
			height = BitmapNative.blinc_bitmap_size(made, true);
		}
		return made;
	}

	/**
		A bitmap of the image file `encoded`, `width` × `height` as the block-compressed forms given to it give, decoded only if
		something needs its pixels, as a GPU that cannot sample block compression does, or an image drawn flat; a mesh texture made
		of a compressed form takes nothing from them. It is shrunk to `maxSide` when it is decoded, if that is given.
	**/
	public static function deferred(encoded:haxe.io.Bytes, width:Int, height:Int, maxSide = 0):Bitmap {
		var made = new Bitmap(-1);
		made.encoded = encoded;
		made.width = width;
		made.height = height;
		made.shrinkTo = maxSide;
		return made;
	}

	/** Whether its pixels are decoded: false until they are needed, for a bitmap made `deferred`. **/
	public function decoded():Bool
		return made >= 0;

	/** Its texture for a mesh's `role` (a `MeshTextures.TextureRole`) already block-compressed, if it has one. **/
	public function compressed(role:Int):Null<ashui.draw3d.BcImage>
		return compressedForms == null ? null : compressedForms.get(role);

	/** Gives it `image` as its texture for `role`, to upload as it is. **/
	public function addCompressed(role:Int, image:ashui.draw3d.BcImage):Void {
		if (compressedForms == null)
			compressedForms = new Map();
		compressedForms.set(role, image);
	}

	/** Lets go of its compressed form for `role`, once the GPU has it. **/
	public function dropCompressed(role:Int):Void
		if (compressedForms != null)
			compressedForms.remove(role);

	/** Frees its decoded pixels, if it has any; what is on the GPU is not touched. **/
	public function freePixels():Void {
		if (made >= 0) BitmapNative.blinc_bitmap_release(made);
		made = -1;
		encoded = null;
	}

	/** Temporarily releases pixels only when every Image use is offscreen and no raw slot or brush escaped. **/
	@:noCompletion public function suspend():Bool {
		if (pinned || disposed || encoded == null || made < 0) return false;
		BitmapNative.blinc_bitmap_release(made);
		made = -1;
		return true;
	}

	/** Image uses are tracked together; other slot consumers pin the pixels conservatively. **/
	@:noCompletion public function imageSlotFor(fit:Brush.ImageFit):Int
		return BASE + decode() * 4 + (fit : Int);

	/** `bytes` of PNG, JPEG or WebP decoded; throws when they are not one. **/
	public static function fromBytes(bytes:haxe.io.Bytes):Bitmap {
		var slot = BitmapNative.blinc_bitmap_decode(bytes, bytes.length);
		if (slot < 0)
			throw "not a PNG, JPEG or WebP image";
		var bitmap = new Bitmap(slot);
		bitmap.encoded = bytes;
		return bitmap;
	}

	/** The image at `path`, a file or what `Assets` has embedded there, read once: loading the same path again gives the same bitmap. **/
	public static function load(path:String):Bitmap {
		var known = loaded.get(path);
		if (known != null)
			return known;
		var made = fromBytes(ashui.core.Assets.bytes(path));
		loaded.set(path, made);
		return made;
	}

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
		if (made < 0 && encoded == null) return null;
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
		if (maxSide > 0) shrinkTo = shrinkTo > 0 ? Std.int(Math.min(shrinkTo, maxSide)) : maxSide;
		if (made < 0) return false;
		if (!BitmapNative.blinc_bitmap_shrink(made, maxSide))
			return false;
		width = BitmapNative.blinc_bitmap_size(made, false);
		height = BitmapNative.blinc_bitmap_size(made, true);
		return true;
	}

	/** Frees its pixels; it must not be drawn after. **/
	public function dispose():Void {
		if (disposed) return;
		disposed = true;
		for (f in disposing)
			f(this);
		freePixels();
		for (k => v in loaded)
			if (v == this)
				loaded.remove(k);
	}

	/** The image record slot that draws it fitted by `fit`. **/
	@:noCompletion public function slotFor(fit:Brush.ImageFit):Int
		return BASE + slot * 4 + (fit : Int);
	#end
}
