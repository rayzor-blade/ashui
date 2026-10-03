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

/** A style rule: what its selectors match takes its declarations. **/
typedef StyleRule = {
	final selectors:Array<Selector>;
	final declarations:Array<Declaration>;

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
}

/**
	A parsed CSS stylesheet: its style rules in source order, the custom
	properties its `:root` rules declare, and its `@keyframes`.

	`Stylesheet.parse` reads CSS text at run time, and the same parser runs
	in macros, so a sheet can be checked when the program is compiled. A
	malformed rule is skipped and reported in `diagnostics` with its line
	and column; the rest of the sheet still applies.
**/
class Stylesheet {
	public final rules:Array<StyleRule> = [];

	/** `:root`'s custom properties, by name without the `--`, in source order. **/
	public final variables:Map<String, String> = [];

	public final keyframes:Map<String, Keyframes> = [];
	public final diagnostics:Array<Diagnostic> = [];

	public function new() {}

	/** `source` parsed; `file` names it in diagnostics. **/
	public static function parse(source:String, ?file:String):Stylesheet
		return new CssParser(source, file).stylesheet();

	/** The errors and warnings, one a line, as `file:line:column: message`. **/
	public function report(?file:String):String {
		var where = file == null ? "" : '$file:';
		return [
			for (d in diagnostics)
				'$where${d.line}:${d.column}: ${d.severity == Error ? "error" : "warning"}: ${d.message}'
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
