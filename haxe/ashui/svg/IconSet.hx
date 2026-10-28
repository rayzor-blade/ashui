package ashui.svg;

#if macro
import haxe.io.Path;
import haxe.macro.Context;
import haxe.macro.Expr;
import sys.FileSystem;
import sys.io.File;
#end

/**
	Generates typed icon constants from directories of SVG files:

	```haxe
	@:build(ashui.svg.IconSet.build(["assets/icons"]))
	class Icons {}

	var play = new ashui.ui.Svg(Icons.PLAY_LINE, {width: 20, height: 20});
	```

	The macro recursively validates and compiles every `.svg` file.
	Filenames become uppercase identifiers: `play-line.svg` → `PLAY_LINE`,
	`4k-line.svg` → `_4K_LINE`. Non-identifier characters become underscores.
	Duplicate names, including conflicts with existing class fields, are errors.
	Folders organize files but do not affect constant names.

	Directories resolve through Haxe class paths. Combine library and app icons:

	```haxe
	@:build(ashui.svg.IconSet.build(["ashui/icons/remix", "assets/own"]))
	class Icons {}
	```

	Each constant lazily creates and caches an `SvgDocument`. The program
	embeds markup, dimensions and tint data; it does not load icon files at
	runtime. Dead-code elimination removes unused icons. File changes,
	additions and removals invalidate the compilation-server cache.
	`currentColor` icons use masks tinted by their element's color.
**/
class IconSet {
	#if macro
	/** Builds the class from the SVG files in `directories`, a directory or an array of them. **/
	public static function build(directories:haxe.extern.EitherType<String, Array<String>>):Array<Field> {
		var named:Array<String> = Std.isOfType(directories, String) ? [(cast directories : String)] : (cast directories : Array<String>);
		return make(named);
	}

	static function make(directories:Array<String>):Array<Field> {
		var pos = Context.currentPos();
		var module = Context.getLocalModule();
		var files:Array<{file:String, root:String}> = [];
		for (directory in directories) {
			var root = try Context.resolvePath(directory) catch (_:Dynamic) Context.error('ICON_SET_DIRECTORY: cannot find $directory on the class path', pos);
			if (!FileSystem.isDirectory(root))
				Context.error('ICON_SET_DIRECTORY: $directory is not a directory', pos);
			root = FileSystem.fullPath(root);
			var found:Array<String> = [];
			walk(root, module, found, new Map(), pos);
			found.sort(Reflect.compare);
			for (file in found)
				files.push({file: file, root: root});
		}
		var fields = Context.getBuildFields();
		var names = new Map<String, String>();
		for (field in fields)
			names.set(field.name, "an existing field");
		for (entry in files) {
			var file = entry.file;
			var source = File.getContent(file);
			var at = Context.makePosition({file: file, min: 0, max: source.length});
			var name = identifier(Path.withoutExtension(Path.withoutDirectory(file)), at);
			var getter = "get_" + name, cache = "__svg_" + name;
			for (generated in [name, getter, cache]) {
				if (names.exists(generated))
					Context.error('ICON_SET_NAME_COLLISION: $generated names both ${names.get(generated)} and $file', at);
				names.set(generated, file);
			}
			Context.registerModuleDependency(module, file);
			var xml = try Xml.parse(source) catch (e:haxe.Exception) Context.error('ICON_SET_XML: ${e.message}', at);
			var document = SvgDocument.compileXml(xml, at);
			fields.push({
				name: name,
				access: [APublic, AStatic],
				kind: FProp("get", "never", macro :ashui.svg.SvgDocument),
				pos: at,
				doc: 'The SVG from ${Path.normalize(file.substr(entry.root.length + 1))}, compiled into the program.'
			});
			fields.push({
				name: cache,
				access: [APrivate, AStatic],
				kind: FVar(macro :ashui.svg.SvgDocument),
				pos: at
			});
			fields.push({
				name: getter,
				access: [APrivate, AStatic, AInline],
				kind: FFun({
					args: [],
					ret: macro :ashui.svg.SvgDocument,
					expr: macro @:pos(at) {
						if ($i{cache} == null)
							$i{cache} = $document;
						return $i{cache};
					}
				}),
				pos: at
			});
		}
		// Unreferenced getters and their embedded markup can be removed even with standard DCE.
		Context.getLocalClass().get().meta.add(":dce", [], pos);
		return fields;
	}

	static function identifier(stem:String, pos:Position):String {
		var name = ~/[^A-Za-z0-9_]/g.replace(stem, "_").toUpperCase();
		if (name.length == 0)
			Context.error("ICON_SET_NAME: an SVG needs a filename", pos);
		var first = name.charCodeAt(0);
		return first >= "0".code && first <= "9".code ? "_" + name : name;
	}

	static function walk(directory:String, module:String, files:Array<String>, active:Map<String, Bool>, pos:Position):Void {
		var full = FileSystem.fullPath(directory);
		if (active.exists(full))
			Context.error('ICON_SET_DIRECTORY_CYCLE: $directory', pos);
		active.set(full, true);
		Context.registerModuleDependency(module, full);
		var entries = FileSystem.readDirectory(full);
		entries.sort(Reflect.compare);
		for (entry in entries) {
			var path = Path.join([full, entry]);
			if (FileSystem.isDirectory(path))
				walk(path, module, files, active, pos);
			else if (Path.extension(entry).toLowerCase() == "svg")
				files.push(path);
		}
		active.remove(full);
	}
	#end
}
