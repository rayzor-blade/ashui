package ashui.css;

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

/**
	Reads CSS text into a `Stylesheet`, by recursive descent over the
	characters. A rule it cannot read is skipped to its closing brace and
	reported; the rest of the sheet still parses. `@media`, `@import`,
	`@supports`, `@font-face` and nested rules are not supported and are
	skipped with a warning, as are attribute selectors with an error.
**/
class CssParser {
	final src:String;
	final file:Null<String>;
	final lineStarts:Array<Int> = [0];
	final sheet = new Stylesheet();
	var at = 0;
	var order = 0;

	public function new(src:String, ?file:String) {
		this.src = src;
		this.file = file;
		for (i in 0...src.length)
			if (code(i) == "\n".code)
				lineStarts.push(i + 1);
	}

	public function stylesheet():Stylesheet {
		while (true) {
			skipSpace();
			if (done())
				break;
			switch peek() {
				case "@".code:
					atRule();
				case "}".code:
					report(Error, "a } with no rule open", at);
					at++;
				case _:
					styleRule();
			}
		}
		return sheet;
	}

	// --- Rules ---

	function styleRule():Void {
		var start = at;
		var prelude = until(["{".code, ";".code, "}".code]);
		if (done() || peek() != "{".code) {
			report(Error, 'expected { after "${StringTools.trim(prelude)}"', start);
			if (!done())
				at++;
			return;
		}
		at++;
		var selectors = try new SelectorReader(prelude, start).list(false) catch (f:Failure) {
			report(Error, f.message, f.at);
			skipBlock();
			return;
		}
		var declarations = block();
		var rootOnly = Lambda.foreach(selectors, s -> s.compounds.length == 1 && isRoot(s.compounds[0]));
		if (rootOnly)
			for (d in declarations)
				if (StringTools.startsWith(d.name, "--"))
					sheet.variables.set(d.name.substr(2), d.value);
		sheet.rules.push({
			selectors: selectors,
			declarations: declarations,
			order: order++,
			line: lineOf(start)
		});
	}

	static function isRoot(c:Compound):Bool
		return c.type == null && c.id == null && c.classes.length == 0 && c.pseudos.length == 1 && c.pseudos[0] == Root;

	function atRule():Void {
		var start = at;
		at++;
		var name = ident().toLowerCase();
		switch name {
			case "keyframes" | "-webkit-keyframes":
				keyframes(start);
			case _:
				report(Warning, '@$name is not supported; skipped', start);
				until(["{".code, ";".code]);
				if (!done() && peek() == "{".code) {
					at++;
					skipBlock();
				} else if (!done())
					at++;
		}
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
			var declarations = block();
			if (!bad)
				frames.push({offsets: offsets, declarations: declarations});
		}
		sheet.keyframes.set(name, {name: name, frames: frames});
	}

	/** The declarations up to the `}` closing a block whose `{` is consumed, consuming it. **/
	function block():Array<Declaration> {
		var out:Array<Declaration> = [];
		while (true) {
			skipSpace();
			if (done()) {
				report(Error, "a block is not closed with }", at);
				return out;
			}
			switch peek() {
				case "}".code:
					at++;
					return out;
				case ";".code:
					at++;
					continue;
				case _:
			}
			var start = at;
			var name = StringTools.trim(until([":".code, ";".code, "{".code, "}".code]));
			if (done() || peek() != ":".code) {
				if (!done() && peek() == "{".code) {
					report(Warning, 'nested rules are not supported; "$name" skipped', start);
					at++;
					skipBlock();
				} else
					report(Error, 'expected : after "$name"', start);
				continue;
			}
			at++;
			var valueAt = at;
			var value = until([";".code, "}".code, "{".code]);
			if (!done() && peek() == "{".code) {
				report(Warning, 'nested rules are not supported; "$name:$value" skipped', start);
				at++;
				skipBlock();
				continue;
			}
			value = StringTools.trim(value);
			var important = false;
			var bang = ~/!\s*important$/i;
			if (bang.match(value)) {
				important = true;
				value = StringTools.trim(bang.matchedLeft());
			}
			if (name == "" || !~/^(--)?[a-zA-Z_-][a-zA-Z0-9_-]*$/.match(name)) {
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
				line: lineOf(start),
				column: columnOf(start)
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

	@:allow(ashui.css.SelectorReader)
	function report(severity:Severity, message:String, index:Int):Void
		sheet.diagnostics.push({
			severity: severity,
			message: message,
			line: lineOf(index),
			column: columnOf(index)
		});

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
					fail("attribute selectors are not supported");
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
		var r = ~/^([+-]?\d*)n([+-]\d+)?$/;
		if (r.match(t)) {
			var a = r.matched(1);
			var b = r.matched(2);
			return {
				a: a == "" || a == "+" ? 1 : a == "-" ? -1 : Std.parseInt(a),
				b: b == null ? 0 : Std.parseInt(b)
			};
		}
		if (~/^[+-]?\d+$/.match(t))
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
