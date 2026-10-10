package ashui.css;

/**
	One `property: value` of a rule. `value` is its text, trimmed, with any
	`!important` removed and noted in `important`; it is read as a typed
	value when the property is applied, so one sheet serves every target.
	A custom property keeps its `--` name.
**/
typedef Declaration = {
	final name:String;
	final value:String;
	final important:Bool;
	final line:Int;
	final column:Int;
}

/** A style rule: what its selectors match takes its declarations, while its media conditions hold. **/
typedef StyleRule = {
	final selectors:Array<Selector>;
	final declarations:Array<Declaration>;

	/** The `@media` query lists it is inside, each of which must hold; null outside any. **/
	final media:Null<Array<Array<Media.MediaQuery>>>;

	/** Its place among the sheet's rules, from 0, for ties in specificity. **/
	final order:Int;

	final line:Int;
}

/** One step of a `@keyframes`: the offsets it stands at, 0 to 1, and its declarations. **/
typedef Keyframe = {
	final offsets:Array<Float>;
	final declarations:Array<Declaration>;
}

/** A `@keyframes name { … }`. **/
typedef Keyframes = {
	final name:String;
	final frames:Array<Keyframe>;
}

enum Severity {
	/** The construct was skipped. **/
	Error;

	/** Parsed, but something in it is not supported or has no effect. **/
	Warning;
}

typedef Diagnostic = {
	final severity:Severity;
	final message:String;
	final line:Int;
	final column:Int;

	/** The file it is in, when it is not the sheet's own: one it imports. **/
	final ?file:String;
}

/**
	Reads an `@import`ed file: `path` as written, `from` the file importing
	it (null for CSS text with no file). Null when there is no such file.
**/
typedef CssLoader = (path:String, from:Null<String>) -> Null<{source:String, file:String}>;

/**
	A parsed CSS stylesheet: its style rules in source order, the custom
	properties its `:root` rules declare, and its `@keyframes`.

	`Stylesheet.parse` reads CSS text at run time, and the same parser runs
	in macros, so a sheet can be checked when the program is compiled, or
	parsed then entirely (see `CompiledCss`). A
	malformed rule is skipped and reported in `diagnostics` with its line
	and column; the rest of the sheet still applies.
**/
class Stylesheet {
	public final rules:Array<StyleRule> = [];

	/** `:root`'s custom properties, by name without the `--`, in source order. **/
	public final variables:Map<String, String> = [];

	public final keyframes:Map<String, Keyframes> = [];

	/** The files it imported, directly or through another, in the order read. **/
	public final imports:Array<String> = [];
	public final diagnostics:Array<Diagnostic> = [];

	/** The CSS text it was parsed from, and the file it names, for the native engine to read. **/
	public var source(default, null):Null<String> = null;

	public var file(default, null):Null<String> = null;

	public function new() {}

	/** A sheet made of what was parsed already: what `CompiledCss` builds at run time. **/
	public static function of(rules:Array<StyleRule>, variables:Map<String, String>, keyframes:Map<String, Keyframes>, imports:Array<String>, ?source:String,
			?file:String):Stylesheet {
		var sheet = new Stylesheet();
		sheet.source = source;
		sheet.file = file;
		for (r in rules)
			sheet.rules.push(r);
		for (k => v in variables)
			sheet.variables.set(k, v);
		for (k => v in keyframes)
			sheet.keyframes.set(k, v);
		for (i in imports)
			sheet.imports.push(i);
		return sheet;
	}

	/**
		`source` parsed; `file` names it in diagnostics and is where an
		`@import` is found from. `load` reads imported files, by default
		from the file system relative to the importing file.
	**/
	public static function parse(source:String, ?file:String, ?load:CssLoader):Stylesheet {
		var sheet = CssParser.parse(source, file, load == null ? readFile : load);
		sheet.source = source;
		sheet.file = file;
		return sheet;
	}

	/** Reads `path` relative to the directory of `from`, or as it is. **/
	public static function readFile(path:String, from:Null<String>):Null<{source:String, file:String}> {
		#if sys
		var file = from == null || haxe.io.Path.isAbsolute(path) ? path : haxe.io.Path.join([haxe.io.Path.directory(from), path]);
		if (!sys.FileSystem.exists(file))
			return null;
		return {source: sys.io.File.getContent(file), file: file};
		#else
		return null;
		#end
	}

	/** The errors and warnings, one a line, as `file:line:column: message`. **/
	public function report(?file:String):String {
		var where = file == null ? "" : '$file:';
		return [
			for (d in diagnostics)
				'${d.file != null ? d.file + ":" : where}${d.line}:${d.column}: ${d.severity == Error ? "error" : "warning"}: ${d.message}'
		].join("\n");
	}

	/** The CSS class names any of its selectors mentions. **/
	public function classNames():Array<String> {
		var seen = new Map<String, Bool>();
		function visit(selectors:Array<Selector>) {
			for (s in selectors)
				for (c in s.compounds) {
					for (name in c.classes)
						seen.set(name, true);
					for (p in c.pseudos)
						switch p {
							case Not(inner) | Is(inner) | Where(inner) | Has(inner): visit(inner);
							case _:
						}
				}
		}
		for (r in rules)
			visit(r.selectors);
		var out = [for (name in seen.keys()) name];
		out.sort(Reflect.compare);
		return out;
	}
}
