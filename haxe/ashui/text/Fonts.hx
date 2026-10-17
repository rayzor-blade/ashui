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
	`font-family: Inter` finds it; the generic families find a bundled face
	that is one of the usual choices: Roboto, Noto Sans or DejaVu Sans for
	`sans-serif`, JetBrains Mono or Fira Code for `monospace`. Register fonts
	at start-up, before any text is laid out.

	```haxe
	Fonts.embed("assets/fonts/Inter.ttf");   // read at compile time
	Fonts.load("fonts/Inter.ttf");           // read when called
	```
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

	#if sys
	/** The font file at `path`, registered; gives how many faces it added. **/
	public static function load(path:String):Int
		return register(sys.io.File.getBytes(path));
	#end
	#end
}
