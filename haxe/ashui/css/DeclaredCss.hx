package ashui.css;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;

/**
	The CSS files a build declares with `-D ashui_css=a.css,b.css`, read
	when it compiles: their errors are compile errors and their warnings
	compile warnings, at the line in the file, and the class names their
	selectors mention are the CSS classes hxx's `class=` accepts beside
	Tw's. A path is found on the class path, or else from the working
	directory.
**/
class DeclaredCss {
	static var cached:Null<Map<String, Bool>> = null;

	/** The class names of the declared sheets, reading them the first time. **/
	public static function classes():Map<String, Bool> {
		if (cached != null)
			return cached;
		var out = new Map<String, Bool>();
		var listed = Context.definedValue("ashui_css");
		if (listed != null)
			for (path in listed.split(",").map(StringTools.trim).filter(p -> p != "")) {
				var file = try Context.resolvePath(path) catch (_:Dynamic) path;
				if (!sys.FileSystem.exists(file))
					Context.error('ashui_css: no file $path', Context.currentPos());
				var source = sys.io.File.getContent(file);
				var sheet = Stylesheet.parse(source, file);
				for (d in sheet.diagnostics) {
					var pos = at(file, source, d.line, d.column);
					if (d.severity == Error)
						Context.error('css: ${d.message}', pos);
					else
						Context.warning('css: ${d.message}', pos);
				}
				for (name in sheet.classNames())
					out.set(name, true);
				// A change to the file recompiles what depends on it.
				Context.registerModuleDependency(Context.getLocalModule(), file);
			}
		return cached = out;
	}

	/** Whether `name` is a class of a declared sheet. **/
	public static inline function has(name:String):Bool
		return classes().exists(name);

	static function at(file:String, source:String, line:Int, column:Int):Position {
		var offset = 0;
		for (_ in 1...line) {
			var next = source.indexOf("\n", offset);
			if (next < 0)
				break;
			offset = next + 1;
		}
		offset += column - 1;
		return Context.makePosition({min: offset, max: offset + 1, file: file});
	}
}
#end
