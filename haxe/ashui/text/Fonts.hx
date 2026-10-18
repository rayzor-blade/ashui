package ashui.text;

#if !macro
import ashui.core.externs.TextNative;
#end
#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
#end

/**
	Fonts a program brings with it, for where the system has none, such as a
	page, or to set text in the same faces on every machine. A registered face
	is found by the family name it carries, as an installed one is, so
	`font-family: Inter` finds it. Register fonts at start-up, before any text
	is laid out.

	```haxe
	Fonts.embed("assets/fonts/Inter.ttf");   // read at compile time
	Fonts.load("fonts/Inter.ttf");           // read when called
	```

	A build defined `wasm` carries Arimo, a sans with the widths of Helvetica
	and Arial, from this library's `fonts/`: text with no family of its own,
	`system-ui` and `sans-serif` are set in it. To use another face, `embed`
	its file in your program and let it carry the family name `Helvetica`,
	`Helvetica Neue` or `Arial`, which is looked for before Arimo; a page has
	no files to read when it runs, so `embed` is the way there, or `Assets.embed`
	for a directory of them and `load` at run time. Define
	`ashui_no_default_fonts` to leave Arimo out. The `monospace` and `serif`
	families have no face in a page unless the program brings one.
**/
class Fonts {
	/** The font file at `path`, relative to the build's working directory, put in the program at compile time and registered when this runs. Gives how many faces it added. **/
	public static macro function embed(path:String):Expr {
		var bytes = try sys.io.File.getBytes(path) catch (e:Dynamic) Context.error('font: cannot read $path', Context.currentPos());
		var name = "ashui.font:" + path;
		Context.addResource(name, bytes);
		return macro ashui.text.Fonts.register(haxe.Resource.getBytes($v{name}));
	}

	// What follows runs in the program, not in the compiler.
	#if !macro
	/** Registers the faces in `bytes`, TTF, OpenType, a collection or WOFF2. Gives how many it added; throws when the bytes are none of those. **/
	public static function register(bytes:haxe.io.Bytes):Int {
		var added = TextNative.blinc_font_register(bytes, bytes.length);
		if (added == 0)
			throw "not a TTF, OpenType or WOFF2 font";
		return added;
	}

	static var defaulted = false;

	/** Registers the fonts the build carries, once; `LayoutTree` calls it before the first tree exists. **/
	@:noCompletion public static function ensureDefaults():Void {
		if (defaulted)
			return;
		defaulted = true;
		for (name in haxe.Resource.listNames())
			if (StringTools.startsWith(name, "ashui.font.default:"))
				register(haxe.Resource.getBytes(name));
	}

	/** The font at `path`, a file or what `Assets` has embedded there, registered; gives how many faces it added. **/
	public static function load(path:String):Int
		return register(ashui.core.Assets.bytes(path));
	#end
}
