package ashui.css;

import ashui.css.Media;
import ashui.css.Selector;
import ashui.css.Stylesheet;

private class Failure {
	public final message:String;
	public final at:Int;

	public function new(message:String, at:Int) {
		this.message = message;
		this.at = at;
	}
}

/** Where rules being read stand: the selectors of the rules they are nested in, as text, and the `@media` lists around them. **/
private typedef Scope = {
	final parents:Null<Array<String>>;
	final media:Null<Array<Array<MediaQuery>>>;
}

private typedef Mixin = {
	final params:Array<{name:String, value:Null<String>}>;
	final body:String;
	final line:Int;
	final column:Int;
}

/** What a sheet and the files it imports share while they are read. **/
private typedef Shared = {
	var order:Int;
	final mixins:Map<String, Mixin>;
	final importing:Array<String>;
	final load:CssLoader;
}

/**
	Reads CSS text into a `Stylesheet`, by recursive descent over the
	characters. A rule it cannot read is skipped to its closing brace and
	reported; the rest of the sheet still parses.

	Beyond plain rules it reads CSS nesting (`&`, nested rules and nested
	`@media`, flattened to plain selectors), `@media` queries kept on each
	rule they hold, `@import`ed files read through the sheet's loader, and
	Sass's `@mixin name($param: default) { … }` with `@include name(args);`,
	a mixin's body read again where it is included with its arguments put
	in. `@supports`, `@font-face`, `@layer` and attribute selectors are not
	supported, and reported.
**/
class CssParser {
	final src:String;
	final file:Null<String>;
	final lineStarts:Array<Int> = [0];
	final sheet:Stylesheet;
	final shared:Shared;

	/** An imported file's diagnostics name it; the sheet's own do not. **/
	final imported:Bool;

	/** Where to report a mixin body's problems: the `@include` it was read for. **/
	final anchor:Null<{line:Int, column:Int, file:Null<String>}>;

	var at = 0;

	public static function parse(source:String, file:Null<String>, load:CssLoader):Stylesheet {
		var sheet = new Stylesheet();
		var shared:Shared = {order: 0, mixins: new Map(), importing: file == null ? [] : [file], load: load};
		new CssParser(source, file, sheet, shared, false, null).rules({parents: null, media: null}, false);
		// A nested rule is pushed before its parent's, which waits for its block; source order again.
		sheet.rules.sort((a, b) -> a.order - b.order);
		return sheet;
	}

	function new(src:String, file:Null<String>, sheet:Stylesheet, shared:Shared, imported:Bool, anchor:Null<{line:Int, column:Int, file:Null<String>}>) {
		this.src = src;
		this.file = file;
		this.sheet = sheet;
		this.shared = shared;
		this.imported = imported;
		this.anchor = anchor;
		for (i in 0...src.length)
			if (code(i) == "\n".code)
				lineStarts.push(i + 1);
	}

	// --- Rules ---

	/** Rules to the end, or with `closed` to the `}` closing a block, consuming it. **/
	function rules(scope:Scope, closed:Bool):Void {
		while (true) {
			skipSpace();
			if (done()) {
				if (closed)
					report(Error, "a block is not closed with }", at);
				return;
			}
			switch peek() {
				case "@".code:
					atRule(scope, null);
				case "}".code:
					at++;
					if (closed)
						return;
					report(Error, "a } with no rule open", at - 1);
				case _:
					styleRule(scope, null);
			}
		}
	}

	/**
		A style rule at `scope`. Its selectors are composed with the parents':
		`&` stands for each, a selector without one is a descendant of each, one
		starting with a combinator relates to each. Its own declarations come
		before the rules nested in it.
	**/
	function styleRule(scope:Scope, into:Null<Array<Declaration>>):Void {
		var start = at;
		var prelude = until(["{".code, ";".code, "}".code]);
		if (done() || peek() != "{".code) {
			report(Error, 'expected { after "${StringTools.trim(prelude)}"', start);
			if (!done() && peek() == ";".code)
				at++;
			return;
		}
		at++;
		var texts = compose(scope.parents, prelude);
		var selectors = try new SelectorReader(texts.join(", "), start).list(false) catch (f:Failure) {
			report(Error, f.message, f.at);
			skipBlock();
			return;
		}
		var inner:Scope = {parents: [for (s in selectors) s.toString()], media: scope.media};
		var order = shared.order++;
		var declarations = block(inner, true);
		emit(selectors, declarations, scope.media, order, start);
	}

	/** Pushes a rule with what it declares; `:root`'s custom properties outside `@media` become the sheet's variables. **/
	/** A selector list on its own, as `query` takes one: `.card > .title, #save`. Throws its error, as text, for one it cannot read. **/
	public static function selectors(text:String):Array<Selector> {
		return try new SelectorReader(text, 0).list(false) catch (f:Failure) throw 'bad selector "$text": ${f.message}';
	}

	function emit(selectors:Array<Selector>, declarations:Array<Declaration>, media:Null<Array<Array<MediaQuery>>>, order:Int, start:Int):Void {
		var rootOnly = media == null && Lambda.foreach(selectors, s -> s.compounds.length == 1 && isRoot(s.compounds[0]));
		if (rootOnly)
			for (d in declarations)
				if (StringTools.startsWith(d.name, "--"))
					sheet.variables.set(d.name.substr(2), d.value);
		sheet.rules.push({
			selectors: selectors,
			declarations: declarations,
			media: media,
			order: order,
			line: lineOf(start)
		});
	}

	/** `nested`'s selectors as text, composed with each of `parents`; `nested` alone at the top. **/
	static function compose(parents:Null<Array<String>>, nested:String):Array<String> {
		var own = CssValue.split(nested, ",");
		if (parents == null)
			return own;
		var out = [];
		for (p in parents) {
			// A parent with combinators keeps its meaning where it is put through :is().
			var wrapped = Patterns.RE0.match(p) ? ':is($p)' : p;
			for (n in own) {
				if (n.indexOf("&") >= 0)
					out.push(StringTools.replace(n, "&", wrapped));
				else
					out.push('$p $n');
			}
		}
		return out;
	}

	static function isRoot(c:Compound):Bool
		return c.type == null && c.id == null && c.classes.length == 0 && c.pseudos.length == 1 && c.pseudos[0] == Root;

	/**
		An at-rule at `scope`. Inside a style rule (`into` its declarations)
		it may be `@media`, whose declarations go to a rule of its own under
		the query, or `@include`, whose declarations join `into`.
	**/
	function atRule(scope:Scope, into:Null<Array<Declaration>>):Void {
		var start = at;
		at++;
		var name = ident().toLowerCase();
		switch name {
			case "media":
				var prelude = StringTools.trim(until(["{".code, ";".code]));
				if (done() || peek() != "{".code) {
					report(Error, "expected { after @media", start);
					if (!done())
						at++;
					return;
				}
				at++;
				var list = try Media.parse(prelude) catch (e:String) {
					report(Error, '@media: $e', start);
					skipBlock();
					return;
				}
				var media = scope.media == null ? [list] : scope.media.concat([list]);
				var inner:Scope = {parents: scope.parents, media: media};
				if (scope.parents == null) {
					rules(inner, true);
				} else {
					var order = shared.order++;
					var declarations = block(inner, true);
					emit(parentSelectors(scope), declarations, media, order, start);
				}
			case "import":
				var prelude = StringTools.trim(until([";".code, "{".code, "}".code]));
				if (!done() && peek() == ";".code)
					at++;
				if (scope.parents != null) {
					report(Error, "@import goes at the top of a sheet, not inside a rule", start);
					return;
				}
				importFile(prelude, scope, start);
			case "mixin":
				defineMixin(start);
			case "include":
				var prelude = StringTools.trim(until([";".code, "{".code, "}".code]));
				if (!done() && peek() == ";".code)
					at++;
				if (into == null) {
					report(Error, "@include goes inside a rule", start);
					return;
				}
				include(prelude, scope, into, start);
			case "keyframes" | "-webkit-keyframes":
				if (scope.parents != null) {
					report(Error, "@keyframes goes at the top of a sheet", start);
					skipStatement();
					return;
				}
				keyframes(start);
			case _:
				report(Warning, '@$name is not supported; skipped', start);
				skipStatement();
		}
	}

	/** The selectors of the rule a nested at-rule stands in. **/
	function parentSelectors(scope:Scope):Array<Selector>
		return try new SelectorReader(scope.parents.join(", "), 0).list(false) catch (_:Failure) [];

	/** Skips an at-rule's prelude and its block or `;`. **/
	function skipStatement():Void {
		until(["{".code, ";".code]);
		if (!done() && peek() == "{".code) {
			at++;
			skipBlock();
		} else if (!done())
			at++;
	}

	/** `@import "a.css"` or `url(a.css)`, with an optional media list: its rules here, under that media. **/
	function importFile(prelude:String, scope:Scope, start:Int):Void {
		var r = Patterns.RE1;
		if (!r.match(prelude)) {
			report(Error, '@import takes a file, "a.css" or url(a.css), not "$prelude"', start);
			return;
		}
		var path = r.matched(2);
		var rest = StringTools.trim(r.matched(3));
		var media = scope.media;
		if (rest != "") {
			var list = try Media.parse(rest) catch (e:String) {
				report(Error, '@import: $e', start);
				return;
			}
			media = media == null ? [list] : media.concat([list]);
		}
		var loaded = shared.load(path, file);
		if (loaded == null) {
			report(Error, '@import: no file $path', start);
			return;
		}
		if (shared.importing.indexOf(loaded.file) >= 0) {
			report(Error, '@import: $path imports itself, through ${shared.importing.join(" -> ")}', start);
			return;
		}
		if (sheet.imports.indexOf(loaded.file) < 0)
			sheet.imports.push(loaded.file);
		shared.importing.push(loaded.file);
		new CssParser(loaded.source, loaded.file, sheet, shared, true, null).rules({parents: null, media: media}, false);
		shared.importing.pop();
	}

	/** `@mixin name($a, $b: default) { … }`: kept as text, read where it is included. **/
	function defineMixin(start:Int):Void {
		skipSpace();
		var name = ident();
		var params = [];
		skipSpace();
		if (!done() && peek() == "(".code) {
			at++;
			var inner = until([")".code]);
			if (!done())
				at++;
			for (p in CssValue.split(inner, ",")) {
				if (p == "")
					continue;
				var colon = p.indexOf(":");
				var pname = StringTools.trim(colon < 0 ? p : p.substr(0, colon));
				if (!StringTools.startsWith(pname, "$")) {
					report(Error, '@mixin $name: a parameter is $$name, not "$pname"', start);
					skipStatement();
					return;
				}
				params.push({name: pname.substr(1), value: colon < 0 ? null : StringTools.trim(p.substr(colon + 1))});
			}
		}
		skipSpace();
		if (name == "" || done() || peek() != "{".code) {
			report(Error, "expected a name and { after @mixin", start);
			skipStatement();
			return;
		}
		at++;
		var bodyStart = at;
		skipBlock();
		shared.mixins.set(name, {
			params: params,
			body: src.substring(bodyStart, at - 1),
			line: lineOf(start),
			column: columnOf(start)
		});
	}

	/** `@include name(args)`: the mixin's body, its parameters replaced by the arguments, read here. **/
	function include(prelude:String, scope:Scope, into:Array<Declaration>, start:Int):Void {
		var call = CssValue.call(prelude);
		var name = call == null ? prelude : call.name;
		var mixin = shared.mixins.get(name);
		if (mixin == null) {
			report(Error, '@include: no mixin $name (a mixin is defined before it is included)', start);
			return;
		}
		var args = call == null ? [] : CssValue.split(call.args, ",").filter(a -> a != "");
		var values = new Map<String, String>();
		var positional = 0;
		for (a in args) {
			var named = Patterns.RE2;
			if (named.match(a))
				values.set(named.matched(1), StringTools.trim(named.matched(2)));
			else if (positional < mixin.params.length)
				values.set(mixin.params[positional++].name, a);
			else {
				report(Error, '@include $name: more arguments than its ${mixin.params.length} parameters', start);
				return;
			}
		}
		for (p in mixin.params)
			if (!values.exists(p.name)) {
				if (p.value == null) {
					report(Error, '@include $name: no value for $$${p.name}', start);
					return;
				}
				values.set(p.name, p.value);
			}
		// Longer names first, so $padding is not read as $pad followed by "ding".
		var names = [for (k in values.keys()) k];
		names.sort((a, b) -> b.length - a.length);
		var body = mixin.body;
		for (n in names)
			body = StringTools.replace(body, "$" + n, values.get(n));
		var here = {line: lineOf(start), column: columnOf(start), file: imported ? file : null};
		var reader = new CssParser(body, file, sheet, shared, imported, anchor != null ? anchor : here);
		for (d in reader.block(scope, false))
			into.push(d);
	}

	function keyframes(start:Int):Void {
		skipSpace();
		var name = if (!done() && (peek() == '"'.code || peek() == "'".code)) quoted() else ident();
		skipSpace();
		if (name == "" || done() || peek() != "{".code) {
			report(Error, "expected a name and { after @keyframes", start);
			until(["{".code]);
			if (!done()) {
				at++;
				skipBlock();
			}
			return;
		}
		at++;
		var frames = [];
		while (true) {
			skipSpace();
			if (done()) {
				report(Error, '@keyframes $name is not closed', start);
				break;
			}
			if (peek() == "}".code) {
				at++;
				break;
			}
			var stepAt = at;
			var prelude = until(["{".code, "}".code]);
			if (done() || peek() != "{".code) {
				report(Error, "expected { after a keyframe offset", stepAt);
				continue;
			}
			at++;
			var offsets = [];
			var bad = false;
			for (part in prelude.split(",")) {
				var p = StringTools.trim(part).toLowerCase();
				var v = p == "from" ? 0.0 : p == "to" ? 1.0 : StringTools.endsWith(p, "%") ? Std.parseFloat(p.substr(0, p.length - 1)) / 100 : Math.NaN;
				if (Math.isNaN(v) || v < 0 || v > 1) {
					report(Error, 'a keyframe offset is from, to or a percentage 0% to 100%, not "$p"', stepAt);
					bad = true;
				}
				offsets.push(v);
			}
			var declarations = block({parents: null, media: null}, true);
			if (!bad)
				frames.push({offsets: offsets, declarations: declarations});
		}
		sheet.keyframes.set(name, {name: name, frames: frames});
	}

	/**
		A block's declarations, to its `}` when `closed` (consumed), else to
		the end; rules and `@media` nested in it are read as rules of their
		own at `scope`, and `@include`s join their declarations to its.
	**/
	function block(scope:Scope, closed:Bool):Array<Declaration> {
		var out:Array<Declaration> = [];
		while (true) {
			skipSpace();
			if (done()) {
				if (closed)
					report(Error, "a block is not closed with }", at);
				return out;
			}
			switch peek() {
				case "}".code:
					at++;
					if (closed)
						return out;
					report(Error, "a } with no block open", at - 1);
					continue;
				case ";".code:
					at++;
					continue;
				case "@".code:
					atRule(scope, out);
					continue;
				case _:
			}
			// A rule nested here reaches { before ; or }; a declaration does not.
			var start = at;
			until([";".code, "{".code, "}".code]);
			var nested = !done() && peek() == "{".code;
			at = start;
			if (nested) {
				if (scope.parents == null) {
					report(Error, "a rule cannot nest here", start);
					until(["{".code]);
					at++;
					skipBlock();
				} else
					styleRule(scope, out);
				continue;
			}
			var name = StringTools.trim(until([":".code, ";".code, "}".code]));
			if (done() || peek() != ":".code) {
				report(Error, 'expected : after "$name"', start);
				continue;
			}
			at++;
			var valueAt = at;
			var value = StringTools.trim(until([";".code, "}".code]));
			var important = false;
			var bang = Patterns.RE3;
			if (bang.match(value)) {
				important = true;
				value = StringTools.trim(bang.matchedLeft());
			}
			if (name == "" || !Patterns.RE4.match(name)) {
				report(Error, '"$name" is not a property name', start);
				continue;
			}
			if (value == "" && !StringTools.startsWith(name, "--")) {
				report(Error, '$name has no value', valueAt);
				continue;
			}
			var custom = StringTools.startsWith(name, "--");
			out.push({
				name: custom ? name : name.toLowerCase(),
				value: value,
				important: important,
				line: anchor != null ? anchor.line : lineOf(start),
				column: anchor != null ? anchor.column : columnOf(start)
			});
		}
	}

	// --- Characters ---

	/**
		The text up to the first of `stops` outside strings, parentheses and
		brackets, or to the end; the stop is not consumed.
	**/
	function until(stops:Array<Int>):String {
		var start = at;
		var depth = 0;
		while (!done()) {
			var c = peek();
			if (c == '"'.code || c == "'".code) {
				quoted();
				continue;
			}
			if (c == "/".code && code(at + 1) == "*".code) {
				skipSpace();
				continue;
			}
			if (c == "\\".code) {
				at += 2;
				continue;
			}
			if (depth == 0 && stops.indexOf(c) >= 0)
				break;
			if (c == "(".code || c == "[".code)
				depth++;
			else if ((c == ")".code || c == "]".code) && depth > 0)
				depth--;
			at++;
		}
		return src.substring(start, Std.int(Math.min(at, src.length)));
	}

	/** Skips past the `}` closing a block whose `{` is consumed, over nested blocks and strings. **/
	function skipBlock():Void {
		var depth = 1;
		while (!done() && depth > 0) {
			var c = peek();
			if (c == '"'.code || c == "'".code) {
				quoted();
				continue;
			}
			if (c == "{".code)
				depth++;
			else if (c == "}".code)
				depth--;
			at++;
		}
	}

	/** A quoted string, its quotes consumed and dropped. **/
	function quoted():String {
		var q = peek();
		var start = at;
		at++;
		var out = new StringBuf();
		while (!done() && peek() != q) {
			if (peek() == "\\".code && at + 1 < src.length) {
				out.addChar(code(at + 1));
				at += 2;
				continue;
			}
			out.addChar(peek());
			at++;
		}
		if (done())
			report(Error, "a string is not closed", start);
		else
			at++;
		return out.toString();
	}

	function ident():String {
		var start = at;
		while (!done() && isIdent(peek()))
			at++;
		return src.substring(start, at);
	}

	function skipSpace():Void {
		while (!done()) {
			var c = peek();
			if (c == " ".code || c == "\t".code || c == "\n".code || c == "\r".code || c == "\x0C".code) {
				at++;
			} else if (c == "/".code && code(at + 1) == "*".code) {
				var end = src.indexOf("*/", at + 2);
				if (end < 0) {
					report(Error, "a comment is not closed", at);
					at = src.length;
				} else
					at = end + 2;
			} else
				break;
		}
	}

	inline function done():Bool
		return at >= src.length;

	inline function peek():Int
		return code(at);

	inline function code(i:Int):Int
		return i < src.length ? StringTools.fastCodeAt(src, i) : -1;

	public static inline function isIdent(c:Int):Bool
		return (c >= "a".code && c <= "z".code) || (c >= "A".code && c <= "Z".code) || (c >= "0".code && c <= "9".code) || c == "-".code
			|| c == "_".code || c >= 0x80;

	// --- Positions ---

	function report(severity:Severity, message:String, index:Int):Void {
		if (anchor != null)
			sheet.diagnostics.push({
				severity: severity,
				message: message + " (in an @include)",
				line: anchor.line,
				column: anchor.column,
				file: anchor.file
			});
		else
			sheet.diagnostics.push({
				severity: severity,
				message: message,
				line: lineOf(index),
				column: columnOf(index),
				file: imported ? file : null
			});
	}

	function lineOf(index:Int):Int {
		var lo = 0, hi = lineStarts.length - 1;
		while (lo < hi) {
			var mid = (lo + hi + 1) >> 1;
			if (lineStarts[mid] <= index)
				lo = mid;
			else
				hi = mid - 1;
		}
		return lo + 1;
	}

	function columnOf(index:Int):Int
		return index - lineStarts[lineOf(index) - 1] + 1;
}

/**

/**
	Reads a selector list, the text before a rule's `{`, at `base` in the
	sheet. Throws a `Failure` for one it cannot read, which skips the rule.
**/
private class SelectorReader {
	final text:String;
	final base:Int;
	var at = 0;

	public function new(text:String, base:Int) {
		this.text = text;
		this.base = base;
	}

	/** Comma-separated selectors to the end; `relative` lets each start with a combinator, as in `:has()`. **/
	public function list(relative:Bool):Array<Selector> {
		var out = [];
		while (true) {
			out.push(complex(relative));
			space();
			if (done())
				break;
			if (peek() == ",".code) {
				at++;
				continue;
			}
			fail('unexpected "${String.fromCharCode(peek())}" in a selector');
		}
		return out;
	}

	function complex(relative:Bool):Selector {
		space();
		var leading:Null<Combinator> = null;
		if (relative) {
			leading = combinator();
			space();
		}
		var compounds = [compound()];
		var combinators = [];
		while (true) {
			var hadSpace = space();
			if (done() || peek() == ",".code || peek() == ")".code)
				break;
			var c = combinator();
			if (c == null) {
				if (!hadSpace)
					fail('unexpected "${String.fromCharCode(peek())}" in a selector');
				c = Descendant;
			}
			space();
			combinators.push(c);
			compounds.push(compound());
		}
		return new Selector(compounds, combinators, leading);
	}

	function combinator():Null<Combinator> {
		if (done())
			return null;
		var c = switch peek() {
			case ">".code: Child;
			case "+".code: NextSibling;
			case "~".code: LaterSibling;
			case _: return null;
		}
		at++;
		return c;
	}

	function compound():Compound {
		var c = new Compound();
		var start = at;
		if (!done() && peek() == "*".code) {
			at++;
		} else if (!done() && CssParser.isIdent(peek()) && !isDigit(peek())) {
			c.type = name().toLowerCase();
		}
		while (!done()) {
			switch peek() {
				case "#".code:
					at++;
					c.id = need(name(), "an id after #");
				case ".".code:
					at++;
					c.classes.push(need(name(), "a class name after ."));
				case "[".code:
					at++;
					c.attributes.push(attribute());
				case ":".code:
					at++;
					if (!done() && peek() == ":".code) {
						at++;
						var pe = name().toLowerCase();
						if (pe != "placeholder")
							fail('::$pe is not supported; ::placeholder is');
						c.pseudoElement = pe;
					} else
						c.pseudos.push(pseudo());
				case _:
					break;
			}
		}
		if (at == start)
			fail(done() ? "a selector is missing" : 'unexpected "${String.fromCharCode(peek())}" in a selector');
		return c;
	}

	/** `name]`, or `name op value]` with the value quoted or a bare word; the `[` is consumed. **/
	function attribute():{name:String, op:Null<String>, value:Null<String>} {
		space();
		var n = need(name(), "an attribute name after [").toLowerCase();
		space();
		if (!done() && peek() == "]".code) {
			at++;
			return {name: n, op: null, value: null};
		}
		var op = "";
		if (!done() && "~|^$*".indexOf(String.fromCharCode(peek())) >= 0) {
			op += String.fromCharCode(peek());
			at++;
		}
		if (done() || peek() != "=".code)
			fail('expected =, ~=, |=, ^=, $$= or *= in [$n]');
		at++;
		op += "=";
		space();
		var value = if (!done() && (peek() == '"'.code || peek() == "'".code)) {
			var q = peek();
			at++;
			var start = at;
			while (!done() && peek() != q)
				at++;
			var v = text.substring(start, at);
			if (done())
				fail("a quoted attribute value is not closed");
			at++;
			v;
		} else
			need(name(), 'a value in [$n$op]');
		space();
		// A case-insensitive flag is accepted and has no effect on these values.
		if (!done() && (peek() == "i".code || peek() == "s".code) && at + 1 < text.length)
			at++;
		space();
		if (done() || peek() != "]".code)
			fail('expected ] after [$n$op"$value"');
		at++;
		return {name: n, op: op, value: value};
	}

	function pseudo():Pseudo {
		var nameAt = at;
		var n = name().toLowerCase();
		if (!done() && peek() == "(".code) {
			at++;
			var inner = argument();
			return switch n {
				case "not": Not(nested(inner, false));
				case "is" | "matches": Is(nested(inner, false));
				case "where": Where(nested(inner, false));
				case "has": Has(nested(inner, true));
				case "nth-child": NthChild(nth(inner.text));
				case "nth-last-child": NthLastChild(nth(inner.text));
				case "nth-of-type": NthOfType(nth(inner.text));
				case "nth-last-of-type": NthLastOfType(nth(inner.text));
				case _: failAt(':$n() is not a pseudo-class this supports', nameAt);
			}
		}
		return switch n {
			case "root": Root;
			case "empty": Empty;
			case "first-child": FirstChild;
			case "last-child": LastChild;
			case "only-child": OnlyChild;
			case "first-of-type": FirstOfType;
			case "last-of-type": LastOfType;
			case "only-of-type": OnlyOfType;
			case "before" | "after" | "first-line" | "first-letter": failAt(':$n is a pseudo-element, which is not supported', nameAt);
			case s if (Selector.STATES.indexOf(s) >= 0): State(s);
			case _: failAt(':$n is not a pseudo-class this supports', nameAt);
		}
	}

	/** The text inside a functional pseudo-class's parentheses, the `)` consumed. **/
	function argument():{text:String, at:Int} {
		var start = at;
		var depth = 1;
		while (!done()) {
			var c = peek();
			if (c == "(".code)
				depth++;
			else if (c == ")".code && --depth == 0)
				break;
			at++;
		}
		if (done())
			failAt("a ( is not closed", start - 1);
		var inner = text.substring(start, at);
		at++;
		return {text: inner, at: start};
	}

	function nested(inner:{text:String, at:Int}, relative:Bool):Array<Selector> {
		if (StringTools.trim(inner.text) == "")
			failAt("a selector is missing", inner.at);
		return new SelectorReader(inner.text, base + inner.at).list(relative);
	}

	/** `odd`, `even`, `b`, `an`, `an+b`, `-n+b`, spaces allowed around the sign. **/
	function nth(s:String):Nth {
		var t = StringTools.replace(StringTools.trim(s).toLowerCase(), " ", "");
		if (t == "odd")
			return {a: 2, b: 1};
		if (t == "even")
			return {a: 2, b: 0};
		var r = Patterns.RE5;
		if (r.match(t)) {
			var a = r.matched(1);
			var b = r.matched(2);
			return {
				a: a == "" || a == "+" ? 1 : a == "-" ? -1 : Std.parseInt(a),
				b: b == null ? 0 : Std.parseInt(b)
			};
		}
		if (Patterns.RE6.match(t))
			return {a: 0, b: Std.parseInt(t)};
		return fail('"$s" is not an an+b pattern, such as 2n+1, odd or 3');
	}

	/** An identifier, with `\` escaping the next character, as Tailwind-style class names need: `.hover\:bg-x`. **/
	function name():String {
		var out = new StringBuf();
		while (!done()) {
			var c = peek();
			if (c == "\\".code && at + 1 < text.length) {
				out.addChar(StringTools.fastCodeAt(text, at + 1));
				at += 2;
			} else if (CssParser.isIdent(c)) {
				out.addChar(c);
				at++;
			} else
				break;
		}
		return out.toString();
	}

	function need(s:String, what:String):String {
		if (s == "")
			fail('expected $what');
		return s;
	}

	/** Skips whitespace and comments; true if there was any. **/
	function space():Bool {
		var start = at;
		while (!done()) {
			var c = peek();
			if (c == " ".code || c == "\t".code || c == "\n".code || c == "\r".code || c == "\x0C".code)
				at++;
			else if (c == "/".code && at + 1 < text.length && StringTools.fastCodeAt(text, at + 1) == "*".code) {
				var end = text.indexOf("*/", at + 2);
				at = end < 0 ? text.length : end + 2;
			} else
				break;
		}
		return at > start;
	}

	static inline function isDigit(c:Int):Bool
		return c >= "0".code && c <= "9".code;

	inline function done():Bool
		return at >= text.length;

	inline function peek():Int
		return StringTools.fastCodeAt(text, at);

	function fail<T>(message:String):T
		return failAt(message, at);

	function failAt<T>(message:String, index:Int):T
		throw new Failure(message, base + index);
}

/** The patterns above, each made once: a `~/…/` written in a function is compiled again every time it runs. **/
private class Patterns {
	public static final RE0 = ~/[\s>+~]/;
	public static final RE1 = ~/^(?:url\(\s*)?(["']?)([^"')\s]+)\1\s*\)?\s*(.*)$/;
	public static final RE2 = ~/^\$([a-zA-Z_-][a-zA-Z0-9_-]*)\s*:\s*(.+)$/s;
	public static final RE3 = ~/!\s*important$/i;
	public static final RE4 = ~/^(--)?[a-zA-Z_-][a-zA-Z0-9_-]*$/;
	public static final RE5 = ~/^([+-]?\d*)n([+-]\d+)?$/;
	public static final RE6 = ~/^[+-]?\d+$/;
}
