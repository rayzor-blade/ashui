package ashui.css;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
#end

/**
	Embeds stylesheets compiled during the Haxe build.
	`CssCompiler` processes each file and its imports. Errors and warnings
	appear at the original source locations. At runtime, the native engine
	decodes the embedded data without parsing CSS or reading files.

	```haxe
	Css.useLibrary("my-library", CompiledCss.file("../css/library.css"));
	```

	Built-in and component styles use this path. `Css.load` and `Css.loadFile`
	parse at runtime instead, which supports live reload.
**/
class CompiledCss {
	/**
		The CSS file at `path`, relative to the file calling this, compiled
		now. The program is compiled again when the file, or one it imports,
		changes.
	**/
	public static macro function file(path:String):ExprOf<Stylesheet> {
		var caller = Context.getPosInfos(Context.currentPos()).file;
		var full = haxe.io.Path.isAbsolute(path) ? path : haxe.io.Path.join([haxe.io.Path.directory(sys.FileSystem.fullPath(caller)), path]);
		full = haxe.io.Path.normalize(full);
		if (!sys.FileSystem.exists(full))
			Context.error('CompiledCss: no file $full', Context.currentPos());
		var compiled = CssCompiler.compile(full);
		DeclaredCss.include(compiled.classes);
		Context.registerModuleDependency(Context.getLocalModule(), full);
		for (imported in compiled.imports)
			Context.registerModuleDependency(Context.getLocalModule(), imported);
		return embed(compiled.bytes, full);
	}

	/** The user-agent stylesheet, `UserAgent.CSS`, compiled now. **/
	public static macro function userAgent():ExprOf<Stylesheet> {
		// Named by its content and written once: a build never rewrites a file another has read.
		var file = haxe.io.Path.join([CssCompiler.cache(), "user-agent-" + haxe.crypto.Md5.encode(UserAgent.CSS) + ".css"]);
		if (!sys.FileSystem.exists(file))
			CssCompiler.writeOnce(file, UserAgent.CSS);
		return embed(CssCompiler.compile(file, "user-agent.css").bytes, "user-agent.css");
	}

	#if macro
	/** The compiled sheet as a resource of the program, and an expression that decodes it. **/
	static function embed(bytes:haxe.io.Bytes, file:String):Expr {
		var name = "ashui-css:" + haxe.crypto.Md5.encode(file);
		Context.addResource(name, bytes);
		return macro ashui.css.Stylesheet.fromResource($v{name}, $v{file});
	}
	#end
}
