package ashui.css;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
#end

/**
	Stylesheets compiled when the program is: blinc_abi's CSS compiler
	(`CssCompiler`) reads the sheet and every file it imports, its errors are
	compile errors and its warnings compile warnings at their line in the
	file they are in, and its compiled form is embedded in the program. At
	run time the native engine decodes it: nothing is parsed and no file is
	read.

	```haxe
	Css.useLibrary("my-library", CompiledCss.file("../css/library.css"));
	```

	`Css.useUserAgent` and `ashui.components.Library` use these. A page's
	own sheets, loaded with `Css.load` or `Css.loadFile`, are parsed at run
	time, so live reload keeps working.
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
		var file = haxe.io.Path.join([CssCompiler.cache(), "user-agent.css"]);
		sys.io.File.saveContent(file, UserAgent.CSS);
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
