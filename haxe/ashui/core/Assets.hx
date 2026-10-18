package ashui.core;

import haxe.io.Bytes;
import haxe.io.Path;
#if macro
import haxe.macro.Context;
import sys.FileSystem;
#end

/**
	The files a program reads when it runs, an image, a font, a model or a
	style sheet, found by their path wherever the program runs. `bytes` and
	`text` give the file at the path when there is one, and otherwise what was
	embedded in the program under that path. `Bitmap.load`, `Fonts.load`,
	`Gltf.load`, `Css.loadFile` and `ThemeBundle.withCssFile` read through them.

	A page has no files, so what a web build reads is embedded when it is built.
	`embed` is a compiler macro that takes a directory:

	```
	haxe ... -D wasm --macro 'ashui.core.Assets.embed("assets", "../assets")'
	```

	Every file under `assets`, folders included, is then embedded under the
	path `../assets/` and its own path in the directory, the path the program
	asks for it by: `Bitmap.load("../assets/map/car.png")` finds `assets/map/car.png`
	as it was when the program was built. A program that only reads files has
	no use for it, and one that embeds its files still reads them from disk when
	they are there.
**/
class Assets {
	/** The file at `path`, or else what is embedded under it; throws when there is neither. **/
	public static function bytes(path:String):Bytes {
		#if sys
		if (sys.FileSystem.exists(path))
			return sys.io.File.getBytes(path);
		#end
		var embedded = haxe.Resource.getBytes(Path.normalize(path));
		if (embedded == null)
			throw 'asset $path: there is no such file, and nothing is embedded under that path';
		return embedded;
	}

	/** The file at `path`, or else what is embedded under it, as text. **/
	public static function text(path:String):String
		return bytes(path).toString();

	#if macro
	/**
		Embeds the files in `directory`, relative to where the compiler runs,
		and in its folders, each under `path` followed by its own path in the
		directory; `path` is `directory` when left out. Files whose names start
		with a dot are left out.
	**/
	public static function embed(directory:String, ?path:String):Void {
		if (!FileSystem.exists(directory) || !FileSystem.isDirectory(directory))
			Context.fatalError('Assets.embed: $directory is not a directory', Context.currentPos());
		add(directory, Path.normalize(path == null ? directory : path));
	}

	static function add(directory:String, named:String):Void {
		var entries = FileSystem.readDirectory(directory);
		entries.sort(Reflect.compare);
		for (entry in entries) {
			if (entry.charAt(0) == ".")
				continue;
			var file = Path.join([directory, entry]), name = Path.join([named, entry]);
			if (FileSystem.isDirectory(file))
				add(file, name);
			else
				Context.addResource(name, sys.io.File.getBytes(file));
		}
	}
	#end
}
