package ashui.css;

/** What a media query is asked about. **/
typedef MediaEnvironment = {
	/** The viewport, in layout units. **/
	final width:Float;

	final height:Float;

	/** Whether the theme's scheme is dark, for `prefers-color-scheme`. **/
	final dark:Bool;
}

/** A comparison in a media feature: `min-width` is `>=`, `max-width` `<=`. **/
enum Compare {
	Eq;
	Lt;
	Le;
	Gt;
	Ge;
}

enum MediaFeature {
	Width(op:Compare, px:Float);
	Height(op:Compare, px:Float);
	AspectRatio(op:Compare, ratio:Float);
	Orientation(portrait:Bool);
	ColorScheme(dark:Bool);
	/** A feature with a fixed answer here: `hover: hover` and `pointer: fine` hold, `print` does not. **/
	Fixed(holds:Bool);
	/** Both bounds of a range written with two comparisons, `400px <= width <= 800px`. **/
	Both(a:MediaFeature, b:MediaFeature);
}

/** One query of a list: an optional `not`, a media type, and features that must all hold. **/
typedef MediaQuery = {
	final not:Bool;
	final features:Array<MediaFeature>;
}

/**
	`@media` conditions: a query list holds when any of its queries does,
	and a rule nested in several `@media` blocks needs every one of them.
**/
class Media {
	/** A query list, as written after `@media`; throws a `String` for one it cannot read. **/
	public static function parse(text:String):Array<MediaQuery> {
		var out = [];
		for (part in CssValue.split(text, ",")) {
			if (part == "")
				throw "an empty media query";
			out.push(query(part));
		}
		return out;
	}

	public static function holds(list:Array<MediaQuery>, env:MediaEnvironment):Bool {
		for (q in list) {
			var all = true;
			for (f in q.features)
				if (!feature(f, env)) {
					all = false;
					break;
				}
			if (all != q.not)
				return true;
		}
		return false;
	}

	/** Whether every list of `all` holds: a rule nested in several `@media` blocks. **/
	public static function allHold(all:Null<Array<Array<MediaQuery>>>, env:MediaEnvironment):Bool {
		if (all == null)
			return true;
		for (list in all)
			if (!holds(list, env))
				return false;
		return true;
	}

	static function query(text:String):MediaQuery {
		var t = StringTools.trim(text).toLowerCase();
		var not = false;
		if (StringTools.startsWith(t, "not ")) {
			not = true;
			t = StringTools.trim(t.substr(4));
		} else if (StringTools.startsWith(t, "only "))
			t = StringTools.trim(t.substr(5));
		var features = [];
		// The media type, then features joined by "and".
		var parts = splitAnd(t);
		for (i => p in parts) {
			if (StringTools.startsWith(p, "(")) {
				if (!StringTools.endsWith(p, ")"))
					throw 'expected a feature in parentheses, not "$p"';
				features.push(parseFeature(StringTools.trim(p.substr(1, p.length - 2))));
			} else if (i == 0) {
				switch p {
					case "all" | "screen":
					case "print" | "speech": features.push(Fixed(false));
					case _: throw 'unknown media type "$p"';
				}
			} else
				throw 'expected a feature in parentheses after "and", not "$p"';
		}
		return {not: not, features: features};
	}

	/** `screen and (min-width: 600px) and (orientation: landscape)` at its top-level "and"s. **/
	static function splitAnd(t:String):Array<String> {
		var out = [];
		var depth = 0, start = 0;
		var i = 0;
		while (i < t.length) {
			var c = t.charAt(i);
			if (c == "(")
				depth++;
			else if (c == ")")
				depth--;
			else if (depth == 0 && t.substr(i, 5) == " and " ) {
				out.push(StringTools.trim(t.substring(start, i)));
				start = i + 5;
				i += 5;
				continue;
			}
			i++;
		}
		out.push(StringTools.trim(t.substring(start)));
		return out.filter(s -> s != "");
	}

	static function parseFeature(f:String):MediaFeature {
		// Range syntax: "width >= 600px", "400px <= width <= 800px".
		var range = ~/^(.+?)\s*(<=|>=|<|>|=)\s*(.+?)(?:\s*(<=|>=|<|>|=)\s*(.+))?$/;
		if (f.indexOf(":") < 0 && range.match(f)) {
			var a = StringTools.trim(range.matched(1)), op1 = range.matched(2), b = StringTools.trim(range.matched(3));
			if (range.matched(4) != null) {
				// a op1 name op2 c: two features.
				var c = StringTools.trim(range.matched(5));
				var lower = ranged(b, flip(compare(op1)), a);
				var upper = ranged(b, compare(range.matched(4)), c);
				return Both(lower, upper);
			}
			if (isName(a))
				return ranged(a, compare(op1), b);
			return ranged(b, flip(compare(op1)), a);
		}
		var colon = f.indexOf(":");
		var name = StringTools.trim(colon < 0 ? f : f.substr(0, colon));
		var value = colon < 0 ? null : StringTools.trim(f.substr(colon + 1));
		return switch name {
			case "width" | "min-width" | "max-width" | "height" | "min-height" | "max-height" | "aspect-ratio" | "min-aspect-ratio" | "max-aspect-ratio":
				if (value == null)
					throw '$name needs a value';
				var op = StringTools.startsWith(name, "min-") ? Ge : StringTools.startsWith(name, "max-") ? Le : Eq;
				var base = StringTools.replace(StringTools.replace(name, "min-", ""), "max-", "");
				ranged(base, op, value);
			case "orientation":
				switch value {
					case "portrait": Orientation(true);
					case "landscape": Orientation(false);
					case _: throw 'orientation is portrait or landscape, not "$value"';
				}
			case "prefers-color-scheme":
				switch value {
					case "dark": ColorScheme(true);
					case "light": ColorScheme(false);
					case _: throw 'prefers-color-scheme is light or dark, not "$value"';
				}
			case "hover" | "any-hover":
				Fixed(value == null || value == "hover");
			case "pointer" | "any-pointer":
				Fixed(value == null || value == "fine");
			case "prefers-reduced-motion":
				Fixed(value == "no-preference");
			case _:
				throw 'unknown media feature "$name"';
		}
	}

	static function isName(s:String):Bool
		return s == "width" || s == "height" || s == "aspect-ratio";

	static function ranged(name:String, op:Compare, value:String):MediaFeature {
		return switch name {
			case "width": Width(op, length(value));
			case "height": Height(op, length(value));
			case "aspect-ratio": AspectRatio(op, ratio(value));
			case _: throw 'unknown media feature "$name"';
		}
	}

	static function length(v:String):Float {
		var l = CssValue.length(v);
		return switch l {
			case Px(x): x;
			case Em(x) | Rem(x): x * 16;
			case _: throw 'a media query length is in px, em or rem, not "$v"';
		}
	}

	static function ratio(v:String):Float {
		var parts = v.split("/");
		return parts.length == 2 ? CssValue.number(parts[0]) / CssValue.number(parts[1]) : CssValue.number(v);
	}

	static function compare(op:String):Compare
		return switch op {
			case "<": Lt;
			case "<=": Le;
			case ">": Gt;
			case ">=": Ge;
			case _: Eq;
		}

	static function flip(c:Compare):Compare
		return switch c {
			case Lt: Gt;
			case Le: Ge;
			case Gt: Lt;
			case Ge: Le;
			case Eq: Eq;
		}

	static function feature(f:MediaFeature, env:MediaEnvironment):Bool {
		inline function cmp(op:Compare, a:Float, b:Float):Bool
			return switch op {
				case Eq: Math.abs(a - b) < 0.001;
				case Lt: a < b;
				case Le: a <= b;
				case Gt: a > b;
				case Ge: a >= b;
			}
		return switch f {
			case Width(op, px): cmp(op, env.width, px);
			case Height(op, px): cmp(op, env.height, px);
			case AspectRatio(op, r): env.height > 0 && cmp(op, env.width / env.height, r);
			case Orientation(portrait): (env.height >= env.width) == portrait;
			case ColorScheme(dark): env.dark == dark;
			case Fixed(holds): holds;
			case Both(a, b): feature(a, env) && feature(b, env);
		}
	}
}
