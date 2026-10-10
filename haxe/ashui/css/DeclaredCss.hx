package ashui.css;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;

/**
	The CSS files a build declares with `-D ashui_css=a.css,b.css`, compiled
	by `CssCompiler` when it compiles: their errors are compile errors and their warnings
	compile warnings, at the line in the file (an imported file's in that
	file), and the class names their selectors mention, imported ones
	included, are the CSS classes hxx's `class=` accepts beside Tw's. A
	path is found on the class path, or else from the working directory;
	an `@import` from the importing file's directory.
**/
class DeclaredCss {
	static var cached:Null<Map<String, Bool>> = null;
	static final compiled = new Map<String, Bool>();

	/** Classes from a CompiledCss sheet are available to the HXX that uses it. **/
	public static function include(classes:Array<String>):Void {
		for (name in classes) {
			compiled.set(name, true);
			if (cached != null) cached.set(name, true);
		}
	}

	/** The class names of the declared sheets, reading them the first time. **/
	public static function classes():Map<String, Bool> {
		if (cached != null)
			return cached;
		var out = compiled.copy();
		var listed = Context.definedValue("ashui_css");
		if (listed != null)
			for (path in listed.split(",").map(StringTools.trim).filter(p -> p != "")) {
				var file = try Context.resolvePath(path) catch (_:Dynamic) path;
				if (!sys.FileSystem.exists(file))
					Context.error('ashui_css: no file $path', Context.currentPos());
				var compiled = CssCompiler.compile(sys.FileSystem.fullPath(file));
				for (name in compiled.classes)
					out.set(name, true);
				// A change to the file, or to one it imports, recompiles what depends on it.
				Context.registerModuleDependency(Context.getLocalModule(), file);
				for (imported in compiled.imports)
					Context.registerModuleDependency(Context.getLocalModule(), imported);
			}
		return cached = out;
	}

	/** Whether `name` is a class of a declared sheet. **/
	public static inline function has(name:String):Bool
		return classes().exists(name);
}
#end
