package ashui.text;

#if !macro
import ashui.core.externs.TextNative;
#end
#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
#end

/**
	Registers bundled fonts by their embedded family names. For example,
	a registered Inter face is available through `font-family: Inter`.
	Register fonts before laying out any text.

	```haxe
	Fonts.embed("assets/fonts/Inter.ttf"); // compile-time asset
	Fonts.load("fonts/Inter.ttf");        // runtime load
	```

	Wasm builds bundle Arimo by default, using Helvetica/Arial-compatible
	widths for unspecified fonts, `system-ui` and `sans-serif`. Embedded
	faces named Helvetica, Helvetica Neue or Arial take precedence.
	Define `ashui_no_default_fonts` to omit Arimo.

	Web builds need embedded assets: use `embed`, or `Assets.embed` for a
	directory followed by `load`. Bundle monospace and serif faces explicitly;
	web builds do not supply defaults for those families.
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
