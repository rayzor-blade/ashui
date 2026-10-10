package ashui.macro;

#if macro
import haxe.Json;
import haxe.io.Path;
import haxe.macro.Compiler;
import haxe.macro.Context;
import sys.FileSystem;
import sys.io.File;
import sys.io.Process;

/**
	The native parts a release package bundles for each platform, listed in
	`native/hdlls.json`: `blinc_abi.hdll`, copied beside HashLink bytecode,
	and the build tools macros run, such as the `blinc-css` CSS compiler.
**/
class NativeInstall {
	static var registered = false;

	/** The library's root, where `native/hdlls.json` is. **/
	public static function root():String {
		var module = Context.resolvePath("ashui/macro/NativeInstall.hx");
		return Path.directory(Path.directory(Path.directory(Path.directory(sys.FileSystem.fullPath(module)))));
	}

	/** This host's bundled tool `name`, or null when the library has none, as a checkout of its repository does. **/
	public static function tool(name:String):Null<String> {
		var entry:Dynamic = Reflect.field(Json.parse(File.getContent(Path.join([root(), "native/hdlls.json"]))), hostPlatform());
		var tools:Dynamic = entry == null ? null : entry.tools;
		var tool:Dynamic = tools == null ? null : Reflect.field(tools, name);
		if (tool == null)
			return null;
		var path = Path.join([root(), tool.packagePath]);
		if (!FileSystem.exists(path))
			return null;
		// haxelib unpacks without file modes: the tool is made executable here.
		if (Sys.systemName() != "Windows")
			Sys.command("chmod", ["+x", path]);
		return path;
	}

	public static function stage():Void {
		if (registered || !Context.defined("hl") || Context.defined("hlc") || Context.defined("ashui_no_hdll"))
			return;
		registered = true;
		Context.onAfterGenerate(() -> {
			var platform = hostPlatform();
			var root = root();
			var manifest:Dynamic = Json.parse(File.getContent(Path.join([root, "native/hdlls.json"])));
			var entry:Dynamic = Reflect.field(manifest, platform);
			if (entry == null) {
				Context.fatalError('ashui has no blinc_abi.hdll for $platform', Context.currentPos());
				return;
			}
			var source = Path.join([root, entry.packagePath]);
			if (!FileSystem.exists(source)) {
				Context.fatalError('ashui is missing $source; install the release Haxelib ZIP, or define ashui_no_hdll and supply blinc_abi.hdll yourself',
					Context.currentPos());
				return;
			}
			var destination = Path.join([Path.directory(Compiler.getOutput()), "blinc_abi.hdll"]);
			if (Path.normalize(source) != Path.normalize(destination))
				File.copy(source, destination);
		});
	}

	public static function hostPlatform():String {
		var os = switch (Sys.systemName()) {
			case "Linux": "linux";
			case "Mac": "macos";
			case "Windows": "windows";
			case other: other.toLowerCase();
		};
		var arch:String;
		if (os == "windows") {
			arch = Sys.getEnv("PROCESSOR_ARCHITEW6432");
			if (arch == null)
				arch = Sys.getEnv("PROCESSOR_ARCHITECTURE");
		} else {
			var process = new Process("uname", ["-m"]);
			arch = StringTools.trim(process.stdout.readAll().toString());
			var status = process.exitCode();
			process.close();
			if (status != 0)
				throw "ashui could not detect the CPU architecture";
		}
		arch = switch (arch == null ? "" : arch.toLowerCase()) {
			case "amd64", "x86_64": "x86_64";
			case "arm64", "aarch64": "aarch64";
			case other: other;
		};
		return '$os-$arch';
	}
}
#end
