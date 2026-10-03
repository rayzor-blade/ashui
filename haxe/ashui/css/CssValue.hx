package ashui.css;

/** A colour: `0xRRGGBB` and an alpha from 0 to 1; or the element's text colour, CSS's `currentcolor`. **/
enum CssColor {
	Rgba(rgb:Int, alpha:Float);
	CurrentColor;
}

/**
	A length as written. `Calc` is resolved, like the units relative to
	something, when the context it depends on is known.
**/
enum CssLength {
	Px(v:Float);
	Percent(v:Float);
	Em(v:Float);
	Rem(v:Float);
	Vw(v:Float);
	Vh(v:Float);
	Vmin(v:Float);
	Vmax(v:Float);
	Calc(e:CalcExpr);
	Auto;
}

/** A `calc()` expression, kept as a tree so units resolve where it is used. **/
enum CalcExpr {
	Num(v:Float);
	Len(l:CssLength);
	Add(a:CalcExpr, b:CalcExpr);
	Sub(a:CalcExpr, b:CalcExpr);
	Mul(a:CalcExpr, b:CalcExpr);
	Div(a:CalcExpr, b:CalcExpr);
	Min(args:Array<CalcExpr>);
	Max(args:Array<CalcExpr>);
	Clamp(lo:CalcExpr, v:CalcExpr, hi:CalcExpr);
	/** An `env(name)`, a value the environment supplies when evaluated, as pointer queries do. **/
	Env(name:String);
}

/** What `CssLength` and `CalcExpr` resolve against; everything in pixels. **/
typedef LengthContext = {
	/** What 100% is. **/
	final percentOf:Float;

	final fontSize:Float;
	final rootFontSize:Float;
	final viewportWidth:Float;
	final viewportHeight:Float;

	/** `env(name)`'s value, or null when the environment has none. **/
	final ?env:String->Null<Float>;
}

/** A transition or animation's easing. **/
enum CssEasing {
	CubicBezier(x1:Float, y1:Float, x2:Float, y2:Float);
	Steps(count:Int, jumpStart:Bool);
}

typedef GradientStop = {
	final color:CssColor;

	/** Where it stands, 0 to 1, or null to be spread between its neighbours, as CSS spreads it. **/
	final offset:Null<Float>;
}

enum CssGradient {
	/** Toward `angle` radians, 0 up and clockwise, as CSS measures it. **/
	Linear(angle:Float, stops:Array<GradientStop>);

	/** A circle or ellipse about a point given as fractions of the box, reaching its farthest corner. **/
	Radial(circle:Bool, x:Float, y:Float, stops:Array<GradientStop>);
}

typedef CssShadow = {
	final inset:Bool;
	final x:CssLength;
	final y:CssLength;
	final blur:CssLength;
	final spread:CssLength;
	final color:CssColor;
}

enum CssTransform {
	Translate(x:CssLength, y:CssLength);
	Scale(x:Float, y:Float);
	/** Radians, clockwise. **/
	Rotate(angle:Float);
	Skew(x:Float, y:Float);
	Matrix(a:Float, b:Float, c:Float, d:Float, e:Float, f:Float);
}

enum CssFilter {
	Brightness(v:Float);
	Contrast(v:Float);
	Grayscale(v:Float);
	Invert(v:Float);
	Saturate(v:Float);
	Sepia(v:Float);
	Opacity(v:Float);
	HueRotate(radians:Float);
	Blur(radius:CssLength);
	DropShadow(shadow:CssShadow);
}

/**
	CSS values read into plain Haxe data, the same at run time and in macros.
	Each reader throws a `String` saying what it expected; the property
	that called it reports that against its declaration.
**/
class CssValue {
	// --- Pieces ---

	/**
		`text` split at top-level `separator`s (a comma, or for whitespace
		` `), outside parentheses and strings, each part trimmed; empty
		parts dropped when splitting at whitespace.
	**/
	public static function split(text:String, separator:String):Array<String> {
		var out = [];
		var depth = 0;
		var quote = -1;
		var start = 0;
		var space = separator == " ";
		for (i in 0...text.length) {
			var c = StringTools.fastCodeAt(text, i);
			if (quote >= 0) {
				if (c == quote)
					quote = -1;
				continue;
			}
			if (c == '"'.code || c == "'".code)
				quote = c;
			else if (c == "(".code)
				depth++;
			else if (c == ")".code)
				depth--;
			else if (depth == 0 && (space ? isSpace(c) : c == StringTools.fastCodeAt(separator, 0))) {
				out.push(StringTools.trim(text.substring(start, i)));
				start = i + 1;
			}
		}
		out.push(StringTools.trim(text.substring(start)));
		return space ? out.filter(s -> s != "") : out;
	}

	/** `name(args)` as its lower-case name and the text of its arguments; null if `text` is not one call. **/
	public static function call(text:String):Null<{name:String, args:String}> {
		var r = ~/^([a-zA-Z-]+)\((.*)\)$/s;
		if (!r.match(StringTools.trim(text)))
			return null;
		// The closing parenthesis must close the opening one.
		var depth = 0;
		var inner = r.matched(2);
		for (i in 0...inner.length) {
			var c = StringTools.fastCodeAt(inner, i);
			if (c == "(".code)
				depth++;
			else if (c == ")".code && --depth < 0)
				return null;
		}
		return depth == 0 ? {name: r.matched(1).toLowerCase(), args: inner} : null;
	}

	/** A number and its unit, lower case, `""` for none; null if `text` is not one. **/
	public static function dimension(text:String):Null<{value:Float, unit:String}> {
		var r = ~/^([+-]?(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?)([a-zA-Z%]*)$/;
		if (!r.match(StringTools.trim(text)))
			return null;
		return {value: Std.parseFloat(r.matched(1)), unit: r.matched(2).toLowerCase()};
	}

	public static function number(text:String):Float {
		var d = dimension(text);
		if (d == null || d.unit != "")
			throw 'expected a number, not "$text"';
		return d.value;
	}

	/** A number or a percentage, as a fraction: `50%` and `0.5` are both 0.5. **/
	public static function amount(text:String):Float {
		var d = dimension(text);
		if (d == null || (d.unit != "" && d.unit != "%"))
			throw 'expected a number or a percentage, not "$text"';
		return d.unit == "%" ? d.value / 100 : d.value;
	}

	/** An angle in radians: `deg`, `rad`, `grad` or `turn`; a bare 0. **/
	public static function angle(text:String):Float {
		var d = dimension(text);
		if (d == null)
			throw 'expected an angle, not "$text"';
		return switch d.unit {
			case "deg": d.value * Math.PI / 180;
			case "rad": d.value;
			case "grad": d.value * Math.PI / 200;
			case "turn": d.value * 2 * Math.PI;
			case "" if (d.value == 0): 0;
			case _: throw 'expected an angle in deg, rad, grad or turn, not "$text"';
		}
	}

	/** A time in seconds: `s` or `ms`. **/
	public static function time(text:String):Float {
		var d = dimension(text);
		if (d == null)
			throw 'expected a time, not "$text"';
		return switch d.unit {
			case "s": d.value;
			case "ms": d.value / 1000;
			case "" if (d.value == 0): 0;
			case _: throw 'expected a time in s or ms, not "$text"';
		}
	}

	// --- Lengths ---

	/** A length; `auto` only where `auto` is allowed. A bare number other than 0 is not a length. **/
	public static function length(text:String, auto = false):CssLength {
		var t = StringTools.trim(text).toLowerCase();
		if (t == "auto") {
			if (!auto)
				throw '"auto" is not allowed here';
			return Auto;
		}
		var c = call(t);
		if (c != null && (c.name == "calc" || c.name == "min" || c.name == "max" || c.name == "clamp"))
			return Calc(calc(t));
		var d = dimension(t);
		if (d == null)
			throw 'expected a length, not "$text"';
		return switch d.unit {
			case "px": Px(d.value);
			case "%": Percent(d.value);
			case "em": Em(d.value);
			case "rem": Rem(d.value);
			case "vw": Vw(d.value);
			case "vh": Vh(d.value);
			case "vmin": Vmin(d.value);
			case "vmax": Vmax(d.value);
			case "" if (d.value == 0): Px(0);
			case "": throw 'a length needs a unit, such as ${d.value}px';
			case u: throw '"$u" is not a length unit this supports';
		}
	}

	/** `l` in pixels; NaN for `auto`. **/
	public static function resolve(l:CssLength, ctx:LengthContext):Float {
		return switch l {
			case Px(v): v;
			case Percent(v): v / 100 * ctx.percentOf;
			case Em(v): v * ctx.fontSize;
			case Rem(v): v * ctx.rootFontSize;
			case Vw(v): v / 100 * ctx.viewportWidth;
			case Vh(v): v / 100 * ctx.viewportHeight;
			case Vmin(v): v / 100 * Math.min(ctx.viewportWidth, ctx.viewportHeight);
			case Vmax(v): v / 100 * Math.max(ctx.viewportWidth, ctx.viewportHeight);
			case Calc(e): evaluate(e, ctx);
			case Auto: Math.NaN;
		}
	}

	/** Whether resolving `l` needs anything beyond pixels. **/
	public static function isFixed(l:CssLength):Bool
		return switch l {
			case Px(_): true;
			case Calc(e): !Lambda.exists(leaves(e), x -> !x);
			case _: false;
		}

	static function leaves(e:CalcExpr):Array<Bool>
		return switch e {
			case Num(_): [true];
			case Len(l): [isFixed(l)];
			case Add(a, b) | Sub(a, b) | Mul(a, b) | Div(a, b): leaves(a).concat(leaves(b));
			case Min(args) | Max(args): [for (x in args) for (y in leaves(x)) y];
			case Clamp(a, b, c): leaves(a).concat(leaves(b)).concat(leaves(c));
			case Env(_): [false];
		}

	// --- calc() ---

	/** A `calc()`, `min()`, `max()` or `clamp()`, or a bare expression. **/
	public static function calc(text:String):CalcExpr {
		var reader = new CalcReader(text);
		var e = reader.expression();
		reader.end();
		return e;
	}

	public static function evaluate(e:CalcExpr, ctx:LengthContext):Float {
		return switch e {
			case Num(v): v;
			case Len(l): resolve(l, ctx);
			case Add(a, b): evaluate(a, ctx) + evaluate(b, ctx);
			case Sub(a, b): evaluate(a, ctx) - evaluate(b, ctx);
			case Mul(a, b): evaluate(a, ctx) * evaluate(b, ctx);
			case Div(a, b): evaluate(a, ctx) / evaluate(b, ctx);
			case Min(args): Lambda.fold(args, (x, m:Float) -> Math.min(evaluate(x, ctx), m), Math.POSITIVE_INFINITY);
			case Max(args): Lambda.fold(args, (x, m:Float) -> Math.max(evaluate(x, ctx), m), Math.NEGATIVE_INFINITY);
			case Clamp(lo, v, hi): Math.max(evaluate(lo, ctx), Math.min(evaluate(v, ctx), evaluate(hi, ctx)));
			case Env(name):
				var v = ctx.env == null ? null : ctx.env(name);
				v == null ? 0 : v;
		}
	}

	/** Whether `e` reads `env()`, so it changes as the environment does. **/
	public static function isDynamic(e:CalcExpr):Bool
		return switch e {
			case Env(_): true;
			case Num(_): false;
			case Len(Calc(inner)): isDynamic(inner);
			case Len(_): false;
			case Add(a, b) | Sub(a, b) | Mul(a, b) | Div(a, b): isDynamic(a) || isDynamic(b);
			case Min(args) | Max(args): Lambda.exists(args, isDynamic);
			case Clamp(a, b, c): isDynamic(a) || isDynamic(b) || isDynamic(c);
		}

	// --- Colours ---

	public static function color(text:String):CssColor {
		var t = StringTools.trim(text).toLowerCase();
		if (t == "currentcolor")
			return CurrentColor;
		if (t == "transparent")
			return Rgba(0, 0);
		if (StringTools.startsWith(t, "#"))
			return hex(t);
		var named = NAMED.get(t);
		if (named != null)
			return Rgba(named, 1);
		var c = call(t);
		if (c == null)
			throw 'expected a colour, not "$text"';
		var parts = c.args.indexOf(",") >= 0 ? split(c.args, ",") : slashed(c.args);
		return switch c.name {
			case "rgb" | "rgba":
				if (parts.length < 3 || parts.length > 4)
					throw '${c.name}() takes three channels and an optional alpha';
				var ch = [for (i in 0...3) channel(parts[i])];
				Rgba((ch[0] << 16) | (ch[1] << 8) | ch[2], parts.length == 4 ? clamp01(amount(parts[3])) : 1);
			case "hsl" | "hsla":
				if (parts.length < 3 || parts.length > 4)
					throw '${c.name}() takes a hue, saturation, lightness and an optional alpha';
				var h = dimension(parts[0]) != null && dimension(parts[0]).unit == "" ? number(parts[0]) * Math.PI / 180 : angle(parts[0]);
				Rgba(hsl(h, clamp01(amount(parts[1])), clamp01(amount(parts[2]))), parts.length == 4 ? clamp01(amount(parts[3])) : 1);
			case n:
				throw '$n() is not a colour this supports; rgb(), hsl(), hex and names are';
		}
	}

	/** Space-separated channels with an optional `/ alpha`, as CSS Color 4 writes them. **/
	static function slashed(args:String):Array<String> {
		var halves = args.split("/");
		var out = split(halves[0], " ");
		if (halves.length == 2)
			out.push(StringTools.trim(halves[1]));
		else if (halves.length > 2)
			throw "a colour has one / before its alpha";
		return out;
	}

	static function channel(text:String):Int {
		var d = dimension(text);
		if (d == null || (d.unit != "" && d.unit != "%"))
			throw 'expected a colour channel, 0 to 255 or a percentage, not "$text"';
		var v = d.unit == "%" ? d.value / 100 * 255 : d.value;
		return Std.int(Math.max(0, Math.min(255, Math.round(v))));
	}

	static function hex(t:String):CssColor {
		var h = t.substr(1);
		if (!~/^[0-9a-f]+$/.match(h))
			throw '"$t" is not a hex colour';
		inline function nibble(i:Int):Int
			return Std.parseInt("0x" + h.charAt(i) + h.charAt(i));
		inline function byte(i:Int):Int
			return Std.parseInt("0x" + h.substr(i, 2));
		return switch h.length {
			case 3: Rgba((nibble(0) << 16) | (nibble(1) << 8) | nibble(2), 1);
			case 4: Rgba((nibble(0) << 16) | (nibble(1) << 8) | nibble(2), nibble(3) / 255);
			case 6: Rgba((byte(0) << 16) | (byte(2) << 8) | byte(4), 1);
			case 8: Rgba((byte(0) << 16) | (byte(2) << 8) | byte(4), byte(6) / 255);
			case _: throw '"$t" is not a hex colour: 3, 4, 6 or 8 digits';
		}
	}

	/** HSL to `0xRRGGBB`, `h` in radians, `s` and `l` 0 to 1. **/
	static function hsl(h:Float, s:Float, l:Float):Int {
		var turns = (h / (2 * Math.PI)) % 1;
		if (turns < 0)
			turns += 1;
		function f(n:Float):Int {
			var k = (n + turns * 12) % 12;
			var a = s * Math.min(l, 1 - l);
			var v = l - a * Math.max(-1, Math.min(Math.min(k - 3, 9 - k), 1));
			return Math.round(v * 255);
		}
		return (f(0) << 16) | (f(8) << 8) | f(4);
	}

	static inline function clamp01(v:Float):Float
		return Math.max(0, Math.min(1, v));

	// --- Easing ---

	public static function easing(text:String):CssEasing {
		var t = StringTools.trim(text).toLowerCase();
		switch t {
			case "linear":
				return CubicBezier(0, 0, 1, 1);
			case "ease":
				return CubicBezier(0.25, 0.1, 0.25, 1);
			case "ease-in":
				return CubicBezier(0.42, 0, 1, 1);
			case "ease-out":
				return CubicBezier(0, 0, 0.58, 1);
			case "ease-in-out":
				return CubicBezier(0.42, 0, 0.58, 1);
			case "step-start":
				return Steps(1, true);
			case "step-end":
				return Steps(1, false);
			case _:
		}
		var c = call(t);
		if (c != null && c.name == "cubic-bezier") {
			var p = split(c.args, ",").map(number);
			if (p.length != 4 || p[0] < 0 || p[0] > 1 || p[2] < 0 || p[2] > 1)
				throw "cubic-bezier() takes four numbers, the first and third 0 to 1";
			return CubicBezier(p[0], p[1], p[2], p[3]);
		}
		if (c != null && c.name == "steps") {
			var p = split(c.args, ",");
			var n = Std.int(number(p[0]));
			if (n < 1)
				throw "steps() takes a count of 1 or more";
			var start = p.length > 1 && (p[1] == "jump-start" || p[1] == "start");
			return Steps(n, start);
		}
		throw 'expected an easing, such as ease-out or cubic-bezier(…), not "$text"';
	}

	// --- Gradients ---

	public static function gradient(text:String):CssGradient {
		var c = call(text);
		if (c == null)
			throw 'expected a gradient, not "$text"';
		var parts = split(c.args, ",");
		return switch c.name {
			case "linear-gradient":
				var angle = Math.PI;
				var first = parts[0].toLowerCase();
				if (StringTools.startsWith(first, "to ")) {
					angle = toward(first.substr(3));
					parts.shift();
				} else if (dimension(first) != null && dimension(first).unit != "%") {
					angle = CssValue.angle(first);
					parts.shift();
				}
				Linear(angle, stops(parts));
			case "radial-gradient":
				var circle = false, x = 0.5, y = 0.5;
				var first = parts[0].toLowerCase();
				if (!looksLikeStop(first)) {
					var words = split(first, " ");
					var at = words.indexOf("at");
					var shape = at < 0 ? words : words.slice(0, at);
					circle = shape.indexOf("circle") >= 0;
					for (w in shape)
						if (w != "circle" && w != "ellipse" && w != "farthest-corner")
							throw 'radial-gradient() sizes other than farthest-corner are not supported: "$w"';
					if (at >= 0) {
						var p = position(words.slice(at + 1));
						x = p.x;
						y = p.y;
					}
					parts.shift();
				}
				Radial(circle, x, y, stops(parts));
			case "conic-gradient" | "repeating-linear-gradient" | "repeating-radial-gradient":
				throw '${c.name}() is not supported';
			case n:
				throw '$n() is not a gradient';
		}
	}

	/** `to right`, `to top left` …, as an angle. **/
	static function toward(side:String):Float {
		var words = split(side, " ");
		var dx = 0.0, dy = 0.0;
		for (w in words)
			switch w {
				case "top": dy = -1;
				case "bottom": dy = 1;
				case "left": dx = -1;
				case "right": dx = 1;
				case _: throw 'expected top, bottom, left or right after "to", not "$w"';
			}
		return Math.atan2(dx, -dy);
	}

	/** `center`, `left top`, `30% 70%` …, as fractions of the box. **/
	static function position(words:Array<String>):{x:Float, y:Float} {
		var x = 0.5, y = 0.5;
		var i = 0;
		for (w in words) {
			switch w {
				case "left": x = 0;
				case "right": x = 1;
				case "top": y = 0;
				case "bottom": y = 1;
				case "center":
				case _:
					var v = amount(w);
					if (i == 0) x = v else y = v;
			}
			i++;
		}
		return {x: x, y: y};
	}

	static function looksLikeStop(part:String):Bool
		return try {
			color(split(part, " ")[0]);
			true;
		} catch (_:String) false;

	static function stops(parts:Array<String>):Array<GradientStop> {
		if (parts.length < 2)
			throw "a gradient takes two colour stops or more";
		var out = [];
		for (p in parts) {
			var words = split(p, " ");
			var c = color(words[0]);
			if (words.length == 1)
				out.push({color: c, offset: null});
			for (i in 1...words.length)
				out.push({color: c, offset: amount(words[i])});
		}
		return out;
	}

	// --- Shadows ---

	/** `box-shadow`'s value: shadows, the first drawn on top; `none` is none. **/
	public static function shadows(text:String):Array<CssShadow> {
		if (StringTools.trim(text).toLowerCase() == "none")
			return [];
		return [for (part in split(text, ",")) shadow(part, true)];
	}

	public static function shadow(text:String, allowInset:Bool):CssShadow {
		var inset = false;
		var lengths = [];
		var colour:Null<CssColor> = null;
		for (w in split(text, " ")) {
			if (w.toLowerCase() == "inset") {
				if (!allowInset)
					throw "inset is for box-shadow";
				inset = true;
			} else if (dimension(w) != null || call(w) != null && call(w).name == "calc") {
				lengths.push(length(w));
			} else
				colour = color(w);
		}
		if (lengths.length < 2 || lengths.length > (allowInset ? 4 : 3))
			throw 'a shadow takes an x and y offset, then a blur${allowInset ? " and a spread" : ""}';
		return {
			inset: inset,
			x: lengths[0],
			y: lengths[1],
			blur: lengths.length > 2 ? lengths[2] : Px(0),
			spread: lengths.length > 3 ? lengths[3] : Px(0),
			color: colour == null ? CurrentColor : colour
		};
	}

	// --- Transforms ---

	public static function transforms(text:String):Array<CssTransform> {
		if (StringTools.trim(text).toLowerCase() == "none")
			return [];
		var out = [];
		for (part in split(text, " ")) {
			var c = call(part);
			if (c == null)
				throw 'expected a transform function, not "$part"';
			var args = split(c.args, ",");
			inline function arity(lo:Int, hi:Int)
				if (args.length < lo || args.length > hi)
					throw '${c.name}() takes ${lo == hi ? '$lo' : '$lo or $hi'} arguments';
			out.push(switch c.name {
				case "translate":
					arity(1, 2);
					Translate(length(args[0]), args.length > 1 ? length(args[1]) : Px(0));
				case "translatex":
					arity(1, 1);
					Translate(length(args[0]), Px(0));
				case "translatey":
					arity(1, 1);
					Translate(Px(0), length(args[0]));
				case "scale":
					arity(1, 2);
					var x = amount(args[0]);
					Scale(x, args.length > 1 ? amount(args[1]) : x);
				case "scalex":
					arity(1, 1);
					Scale(amount(args[0]), 1);
				case "scaley":
					arity(1, 1);
					Scale(1, amount(args[0]));
				case "rotate" | "rotatez":
					arity(1, 1);
					Rotate(angle(args[0]));
				case "skew":
					arity(1, 2);
					Skew(angle(args[0]), args.length > 1 ? angle(args[1]) : 0);
				case "skewx":
					arity(1, 1);
					Skew(angle(args[0]), 0);
				case "skewy":
					arity(1, 1);
					Skew(0, angle(args[0]));
				case "matrix":
					arity(6, 6);
					var m = args.map(number);
					Matrix(m[0], m[1], m[2], m[3], m[4], m[5]);
				case n:
					throw '$n() is not a 2D transform this supports';
			});
		}
		return out;
	}

	// --- Filters ---

	public static function filters(text:String):Array<CssFilter> {
		if (StringTools.trim(text).toLowerCase() == "none")
			return [];
		var out = [];
		for (part in split(text, " ")) {
			var c = call(part);
			if (c == null)
				throw 'expected a filter function, not "$part"';
			var a = StringTools.trim(c.args);
			out.push(switch c.name {
				case "brightness": Brightness(amount(a));
				case "contrast": Contrast(amount(a));
				case "grayscale": Grayscale(amount(a));
				case "invert": Invert(amount(a));
				case "saturate": Saturate(amount(a));
				case "sepia": Sepia(amount(a));
				case "opacity": Opacity(amount(a));
				case "hue-rotate": HueRotate(angle(a));
				case "blur": Blur(length(a == "" ? "0" : a));
				case "drop-shadow": DropShadow(shadow(a, false));
				case n: throw '$n() is not a filter';
			});
		}
		return out;
	}

	static inline function isSpace(c:Int):Bool
		return c == " ".code || c == "\t".code || c == "\n".code || c == "\r".code || c == "\x0C".code;

	/** CSS's named colours. **/
	static final NAMED:Map<String, Int> = [
		"aliceblue" => 0xf0f8ff, "antiquewhite" => 0xfaebd7, "aqua" => 0x00ffff, "aquamarine" => 0x7fffd4, "azure" => 0xf0ffff,
		"beige" => 0xf5f5dc, "bisque" => 0xffe4c4, "black" => 0x000000, "blanchedalmond" => 0xffebcd, "blue" => 0x0000ff,
		"blueviolet" => 0x8a2be2, "brown" => 0xa52a2a, "burlywood" => 0xdeb887, "cadetblue" => 0x5f9ea0, "chartreuse" => 0x7fff00,
		"chocolate" => 0xd2691e, "coral" => 0xff7f50, "cornflowerblue" => 0x6495ed, "cornsilk" => 0xfff8dc, "crimson" => 0xdc143c,
		"cyan" => 0x00ffff, "darkblue" => 0x00008b, "darkcyan" => 0x008b8b, "darkgoldenrod" => 0xb8860b, "darkgray" => 0xa9a9a9,
		"darkgreen" => 0x006400, "darkgrey" => 0xa9a9a9, "darkkhaki" => 0xbdb76b, "darkmagenta" => 0x8b008b, "darkolivegreen" => 0x556b2f,
		"darkorange" => 0xff8c00, "darkorchid" => 0x9932cc, "darkred" => 0x8b0000, "darksalmon" => 0xe9967a, "darkseagreen" => 0x8fbc8f,
		"darkslateblue" => 0x483d8b, "darkslategray" => 0x2f4f4f, "darkslategrey" => 0x2f4f4f, "darkturquoise" => 0x00ced1,
		"darkviolet" => 0x9400d3, "deeppink" => 0xff1493, "deepskyblue" => 0x00bfff, "dimgray" => 0x696969, "dimgrey" => 0x696969,
		"dodgerblue" => 0x1e90ff, "firebrick" => 0xb22222, "floralwhite" => 0xfffaf0, "forestgreen" => 0x228b22, "fuchsia" => 0xff00ff,
		"gainsboro" => 0xdcdcdc, "ghostwhite" => 0xf8f8ff, "gold" => 0xffd700, "goldenrod" => 0xdaa520, "gray" => 0x808080,
		"green" => 0x008000, "greenyellow" => 0xadff2f, "grey" => 0x808080, "honeydew" => 0xf0fff0, "hotpink" => 0xff69b4,
		"indianred" => 0xcd5c5c, "indigo" => 0x4b0082, "ivory" => 0xfffff0, "khaki" => 0xf0e68c, "lavender" => 0xe6e6fa,
		"lavenderblush" => 0xfff0f5, "lawngreen" => 0x7cfc00, "lemonchiffon" => 0xfffacd, "lightblue" => 0xadd8e6, "lightcoral" => 0xf08080,
		"lightcyan" => 0xe0ffff, "lightgoldenrodyellow" => 0xfafad2, "lightgray" => 0xd3d3d3, "lightgreen" => 0x90ee90,
		"lightgrey" => 0xd3d3d3, "lightpink" => 0xffb6c1, "lightsalmon" => 0xffa07a, "lightseagreen" => 0x20b2aa,
		"lightskyblue" => 0x87cefa, "lightslategray" => 0x778899, "lightslategrey" => 0x778899, "lightsteelblue" => 0xb0c4de,
		"lightyellow" => 0xffffe0, "lime" => 0x00ff00, "limegreen" => 0x32cd32, "linen" => 0xfaf0e6, "magenta" => 0xff00ff,
		"maroon" => 0x800000, "mediumaquamarine" => 0x66cdaa, "mediumblue" => 0x0000cd, "mediumorchid" => 0xba55d3,
		"mediumpurple" => 0x9370db, "mediumseagreen" => 0x3cb371, "mediumslateblue" => 0x7b68ee, "mediumspringgreen" => 0x00fa9a,
		"mediumturquoise" => 0x48d1cc, "mediumvioletred" => 0xc71585, "midnightblue" => 0x191970, "mintcream" => 0xf5fffa,
		"mistyrose" => 0xffe4e1, "moccasin" => 0xffe4b5, "navajowhite" => 0xffdead, "navy" => 0x000080, "oldlace" => 0xfdf5e6,
		"olive" => 0x808000, "olivedrab" => 0x6b8e23, "orange" => 0xffa500, "orangered" => 0xff4500, "orchid" => 0xda70d6,
		"palegoldenrod" => 0xeee8aa, "palegreen" => 0x98fb98, "paleturquoise" => 0xafeeee, "palevioletred" => 0xdb7093,
		"papayawhip" => 0xffefd5, "peachpuff" => 0xffdab9, "peru" => 0xcd853f, "pink" => 0xffc0cb, "plum" => 0xdda0dd,
		"powderblue" => 0xb0e0e6, "purple" => 0x800080, "rebeccapurple" => 0x663399, "red" => 0xff0000, "rosybrown" => 0xbc8f8f,
		"royalblue" => 0x4169e1, "saddlebrown" => 0x8b4513, "salmon" => 0xfa8072, "sandybrown" => 0xf4a460, "seagreen" => 0x2e8b57,
		"seashell" => 0xfff5ee, "sienna" => 0xa0522d, "silver" => 0xc0c0c0, "skyblue" => 0x87ceeb, "slateblue" => 0x6a5acd,
		"slategray" => 0x708090, "slategrey" => 0x708090, "snow" => 0xfffafa, "springgreen" => 0x00ff7f, "steelblue" => 0x4682b4,
		"tan" => 0xd2b48c, "teal" => 0x008080, "thistle" => 0xd8bfd8, "tomato" => 0xff6347, "turquoise" => 0x40e0d0,
		"violet" => 0xee82ee, "wheat" => 0xf5deb3, "white" => 0xffffff, "whitesmoke" => 0xf5f5f5, "yellow" => 0xffff00,
		"yellowgreen" => 0x9acd32
	];
}

/** Reads a `calc()` expression: `+` and `-` (spaced, as CSS requires), `*` and `/`, parentheses, functions. **/
private class CalcReader {
	final text:String;
	var at = 0;

	public function new(text:String) {
		this.text = StringTools.trim(text);
	}

	public function end():Void {
		space();
		if (at < text.length)
			throw 'unexpected "${text.substr(at)}" in calc()';
	}

	public function expression():CalcExpr {
		var left = term();
		while (true) {
			var before = at;
			var spaced = space();
			if (at >= text.length || (peek() != "+".code && peek() != "-".code)) {
				at = before;
				return left;
			}
			var op = peek();
			at++;
			if (!spaced || !space())
				throw "calc() needs spaces around + and -";
			var right = term();
			left = op == "+".code ? Add(left, right) : Sub(left, right);
		}
	}

	function term():CalcExpr {
		var left = factor();
		while (true) {
			var before = at;
			space();
			if (at >= text.length || (peek() != "*".code && peek() != "/".code)) {
				at = before;
				return left;
			}
			var op = peek();
			at++;
			space();
			var right = factor();
			left = op == "*".code ? Mul(left, right) : Div(left, right);
		}
	}

	function factor():CalcExpr {
		space();
		if (at >= text.length)
			throw "calc() ends early";
		if (peek() == "(".code) {
			at++;
			var inner = expression();
			space();
			expect(")".code);
			return inner;
		}
		var start = at;
		while (at < text.length && ~/[a-zA-Z0-9.%_+-]/.match(text.charAt(at)) && !(at > start && (peek() == "+".code || peek() == "-".code)
				&& !~/[eE]/.match(text.charAt(at - 1))))
			at++;
		var word = text.substring(start, at);
		if (at < text.length && peek() == "(".code) {
			at++;
			var name = word.toLowerCase();
			if (name == "env") {
				var close = text.indexOf(")", at);
				var args = CssValue.split(text.substring(at, close), ",");
				at = close + 1;
				return Env(StringTools.trim(args[0]));
			}
			var args = [expression()];
			space();
			while (at < text.length && peek() == ",".code) {
				at++;
				args.push(expression());
				space();
			}
			expect(")".code);
			return switch name {
				case "calc" if (args.length == 1): args[0];
				case "min": Min(args);
				case "max": Max(args);
				case "clamp" if (args.length == 3): Clamp(args[0], args[1], args[2]);
				case _: throw '$name() is not a calc() function this supports';
			}
		}
		var d = CssValue.dimension(word);
		if (d == null)
			throw 'unexpected "$word" in calc()';
		// Angles count in radians and times in seconds, so a calc() of either is a number.
		return switch d.unit {
			case "": Num(d.value);
			case "deg" | "rad" | "grad" | "turn": Num(CssValue.angle(word));
			case "s" | "ms": Num(CssValue.time(word));
			case _: Len(CssValue.length(word));
		}
	}

	function expect(c:Int):Void {
		if (at >= text.length || peek() != c)
			throw 'expected "${String.fromCharCode(c)}" in calc()';
		at++;
	}

	function space():Bool {
		var start = at;
		while (at < text.length && (peek() == " ".code || peek() == "\t".code || peek() == "\n".code))
			at++;
		return at > start;
	}

	inline function peek():Int
		return StringTools.fastCodeAt(text, at);
}
