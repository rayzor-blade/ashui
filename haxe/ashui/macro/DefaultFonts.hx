package ashui.macro;

#if macro
import haxe.io.Path;
import haxe.macro.Context;
import sys.FileSystem;
import sys.io.File;

/**
	The fonts a web build carries, from the library's `fonts/`: added to the
	program as resources, which `ashui.text.Fonts` registers before any text is
	laid out. Only a build defined `wasm` has them; `ashui_no_default_fonts`
	leaves them out.
**/
class DefaultFonts {
	/** Each font's resource name starts with this. **/
	public static inline var PREFIX = "ashui.font.default:";

	static var registered = false;

	public static function stage():Void {
		if (registered || !Context.defined("wasm") || Context.defined("ashui_no_default_fonts"))
			return;
		registered = true;
		var directory = Path.join([NativeInstall.root(), "fonts"]);
		for (file in ["Arimo.woff2", "Arimo-Italic.woff2"]) {
			var path = Path.join([directory, file]);
			if (!FileSystem.exists(path)) {
				Context.fatalError('ashui is missing $path; install the release Haxelib ZIP, or define ashui_no_default_fonts and bring a font with Fonts.embed',
					Context.currentPos());
				return;
			}
			Context.addResource(PREFIX + file, File.getBytes(path));
		}
	}
}
#end
