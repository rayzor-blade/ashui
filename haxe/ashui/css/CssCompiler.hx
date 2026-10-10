package ashui.css;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;

/**
	CSS compiled when the program is: blinc_abi's `blinc-css` tool reads a
	sheet and the files it imports, and gives its compiled form, the files it
	imported and the class names its selectors use. Its errors become
	compile errors and its warnings compile warnings, at their line in the
	file they are in.

	The tool is found in this order: the `BLINC_CSS` environment variable;
	the one a release package bundles for this platform (see
	`NativeInstall`); or, in a checkout of the repository, one built once with
	`cargo install` from the blinc_abi revision `Cargo.toml` pins, into
	`.ashui/blinc-css/<revision>`.
**/
class CssCompiler {
	static var found:Null<String> = null;

	/** What compiling a sheet gave: its compiled bytes, the files it imported, and its classes. **/
	public static function compile(file:String, ?shownAs:String):{bytes:haxe.io.Bytes, imports:Array<String>, classes:Array<String>} {
		var out = haxe.io.Path.join([cache(), haxe.crypto.Md5.encode(file) + ".bcss"]);
		var p = new sys.io.Process(tool(), [file, "-o", out, "--manifest"]);
		var stdout = p.stdout.readAll().toString();
		var stderr = p.stderr.readAll().toString();
		var code = p.exitCode();
		p.close();
		if (code > 1)
			Context.error('blinc-css: $stderr', Context.currentPos());
		report(stderr, file, shownAs);
		var manifest:{imports:Array<String>, classes:Array<String>} = haxe.Json.parse(stdout);
		return {bytes: sys.io.File.getBytes(out), imports: manifest.imports, classes: manifest.classes};
	}

	/** Each diagnostic, `file:line:column: severity: message`, at its place; errors after warnings, the first ending the build. **/
	static function report(stderr:String, file:String, ?shownAs:String):Void {
		var line = ~/^(.*):([0-9]+):([0-9]+): (error|warning): (.*)$/;
		var errors = [];
		for (text in stderr.split("\n"))
			if (line.match(StringTools.trim(text))) {
				var where = line.matched(1);
				var pos = position(where, Std.parseInt(line.matched(2)), Std.parseInt(line.matched(3)), where == file ? shownAs : null);
				var message = 'css: ${line.matched(5)}';
				if (line.matched(4) == "error")
					errors.push({message: message, pos: pos});
				else
					Context.warning(message, pos);
			}
		for (e in errors)
			Context.error(e.message, e.pos);
	}

	/** Line and column of `file` as a position: in the file itself, or named `shownAs` for CSS that is not one. **/
	static function position(file:String, line:Int, column:Int, ?shownAs:String):Position {
		var source = try sys.io.File.getContent(file) catch (_:Dynamic) "";
		var offset = 0;
		for (_ in 1...line) {
			var next = source.indexOf("\n", offset);
			if (next < 0)
				break;
			offset = next + 1;
		}
		offset += column - 1;
		return Context.makePosition({min: offset, max: offset + 1, file: shownAs != null ? shownAs : file});
	}

	/** Where compiled sheets are written on the way to the program: the system's temporary directory. **/
	public static function cache():String {
		var base = Sys.getEnv("TMPDIR");
		if (base == null || base == "")
			base = Sys.getEnv("TEMP");
		if (base == null || base == "")
			base = haxe.io.Path.join([Sys.getCwd(), ".ashui"]);
		var dir = haxe.io.Path.join([base, "ashui-css"]);
		sys.FileSystem.createDirectory(dir);
		return dir;
	}

	/** This library's root. **/
	public static inline function root():String
		return ashui.macro.NativeInstall.root();

	/** The `blinc-css` tool, built the first time when none is found. **/
	public static function tool():String {
		if (found != null)
			return found;
		var exe = Sys.systemName() == "Windows" ? "blinc-css.exe" : "blinc-css";
		var env = Sys.getEnv("BLINC_CSS");
		if (env != null && env != "")
			return found = env;
		var bundled = ashui.macro.NativeInstall.tool("blinc-css");
		if (bundled != null)
			return found = bundled;
		var manifest = sys.io.File.getContent(haxe.io.Path.join([root(), "Cargo.toml"]));
		var pin = ~/blinc_abi"?,? *git *= *"([^"]+)", *rev *= *"([0-9a-f]+)"/;
		if (!pin.match(manifest))
			Context.fatalError("blinc-css: no blinc_abi revision in Cargo.toml; set BLINC_CSS to the tool", Context.currentPos());
		var dir = haxe.io.Path.join([root(), ".ashui", "blinc-css", pin.matched(2)]);
		var built = haxe.io.Path.join([dir, "bin", exe]);
		if (!sys.FileSystem.exists(built)) {
			Sys.println('[ashui] building blinc-css ${pin.matched(2).substr(0, 7)}, once');
			var code = Sys.command("cargo", [
				"install", "--quiet", "--git", pin.matched(1), "--rev", pin.matched(2), "blinc_abi", "--bin", "blinc-css", "--no-default-features",
				"--features", "css-cli", "--root", dir
			]);
			if (code != 0 || !sys.FileSystem.exists(built))
				Context.fatalError("blinc-css: cargo install failed; set BLINC_CSS to the tool", Context.currentPos());
		}
		return found = built;
	}
}
#end
