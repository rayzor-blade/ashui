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
	A CSS stylesheet, parsed by the native CSS engine, which keeps it:
	`Stylesheet.parse` reads CSS text, and `CompiledCss` compiles a sheet
	with the program. A malformed rule is skipped and reported in
	`diagnostics` with its line and column; the rest of the sheet still
	applies.
**/
class Stylesheet {
	/** The files it imported, directly or through another, in the order read. **/
	public final imports:Array<String> = [];
	public final diagnostics:Array<Diagnostic> = [];

	/** The CSS text it was parsed from, and the file it names. **/
	public var source(default, null):Null<String> = null;

	public var file(default, null):Null<String> = null;

	/** The program resource holding its compiled form, for one `CompiledCss` made. **/
	var resource:Null<String> = null;

	#if (hl && !macro)
	/** The sheet as the native engine parsed it; made when first asked for. **/
	var parsed:Null<hl.Abstract<"blinc_css_sheet">> = null;

	/** The native engine's parse of it, made the first time it is asked for. **/
	public function native():hl.Abstract<"blinc_css_sheet"> {
		if (parsed == null) {
			if (resource != null) {
				var bytes = haxe.Resource.getBytes(resource);
				parsed = ashui.core.externs.CssNative.blinc_css_decode(@:privateAccess bytes.b, bytes.length);
				if (parsed == null)
					throw 'Stylesheet: the compiled sheet $file does not decode';
			} else
				parsed = ashui.core.externs.CssNative.blinc_css_parse(@:privateAccess (source == null ? "" : source).toUtf8(),
					@:privateAccess (file == null ? "" : file).toUtf8());
			diagnostics.resize(0);
			for (record in records(ashui.core.externs.CssNative.blinc_css_sheet_diagnostics(parsed))) {
				var f = record.split("\x02");
				diagnostics.push({
					severity: f[0] == "error" ? Error : Warning,
					line: Std.parseInt(f[1]),
					column: Std.parseInt(f[2]),
					file: f[3] == "" ? null : f[3],
					message: f[4]
				});
			}
			imports.resize(0);
			for (record in records(ashui.core.externs.CssNative.blinc_css_sheet_imports(parsed)))
				imports.push(record);
		}
		return parsed;
	}

	/** Every declaration of its rules: name, line and column. **/
	public function declared():Array<{name:String, line:Int, column:Int}> {
		return [
			for (record in records(ashui.core.externs.CssNative.blinc_css_sheet_declared(native()))) {
				var f = record.split("\x02");
				{name: f[0], line: Std.parseInt(f[1]), column: Std.parseInt(f[2])};
			}
		];
	}

	static function records(b:hl.Bytes):Array<String> {
		var text = b == null ? "" : @:privateAccess String.fromUTF8(b);
		return text == "" ? [] : text.split("\x01");
	}
	#end

	function new() {}

	/** The sheet `CompiledCss` compiled into program resource `name`, decoded natively when first used. **/
	public static function fromResource(name:String, file:String):Stylesheet {
		var sheet = new Stylesheet();
		sheet.resource = name;
		sheet.file = file;
		return sheet;
	}

	/** A sheet of CSS text, parsed natively when first used. **/
	static function compiled(source:String, file:Null<String>):Stylesheet {
		var sheet = new Stylesheet();
		sheet.source = source;
		sheet.file = file;
		return sheet;
	}

	/**
		`source` parsed; `file` names it in diagnostics and is where an
		`@import` is read from, relative to it.
	**/
	public static function parse(source:String, ?file:String):Stylesheet {
		var sheet = compiled(source, file);
		#if (hl && !macro)
		sheet.native();
		#end
		return sheet;
	}

	/** The errors and warnings, one a line, as `file:line:column: message`. **/
	public function report(?file:String):String {
		var where = file == null ? "" : '$file:';
		return [
			for (d in diagnostics)
				'${d.file != null ? d.file + ":" : where}${d.line}:${d.column}: ${d.severity == Error ? "error" : "warning"}: ${d.message}'
		].join("\n");
	}
}
