package ashui.components;

#if macro
import haxe.macro.Context;
#end

/** The library's stylesheet, read when the program is compiled. **/
class LibraryCss {
	/** `components/css/components.css`, as a string; the program is compiled again when it changes. **/
	public static macro function read() {
		var here = Context.getPosInfos(Context.currentPos()).file;
		var dir = haxe.io.Path.directory(sys.FileSystem.fullPath(here));
		var path = haxe.io.Path.normalize(dir + "/../../../css/components.css");
		Context.registerModuleDependency(Context.getLocalModule(), path);
		return macro $v{sys.io.File.getContent(path)};
	}
}
