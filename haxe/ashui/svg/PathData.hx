package ashui.svg;

/**
	One step of an outline, in absolute coordinates. An SVG path's `d`
	attribute is a list of these, written compactly: relative steps,
	horizontal and vertical lines and smooth curves that reflect the last
	control point all become one of these.
**/
enum PathCommand {
	MoveTo(x:Float, y:Float);
	LineTo(x:Float, y:Float);
	/** A cubic Bézier curve through two control points. **/
	CubicTo(x1:Float, y1:Float, x2:Float, y2:Float, x:Float, y:Float);
	/** A quadratic Bézier curve through one control point. **/
	QuadTo(x1:Float, y1:Float, x:Float, y:Float);
	/** An elliptical arc of radii `rx`, `ry`, its x axis turned by `rotation` degrees, to `(x, y)`. **/
	ArcTo(rx:Float, ry:Float, rotation:Float, largeArc:Bool, sweep:Bool, x:Float, y:Float);
	Close;
}

/**
	Reads and writes SVG path data, the language of a `<path>`'s `d`
	attribute: `M 4 12 l 5 5 L 20 6` and its compact forms such as
	`M4,12l5,5L20,6` or `M.5-1.5.5.5`.
**/
class PathData {
	/** The commands of `d`, absolute; throws `SvgError` at the first mistake. **/
	public static function parse(d:String):Array<PathCommand> {
		return new PathReader(d).read();
	}

	/** `commands` as path data, every step absolute and spelled out. **/
	public static function write(commands:Array<PathCommand>):String {
		var out = new StringBuf();
		for (c in commands) {
			if (out.length > 0)
				out.add(" ");
			switch c {
				case MoveTo(x, y):
					out.add('M${n(x)} ${n(y)}');
				case LineTo(x, y):
					out.add('L${n(x)} ${n(y)}');
				case CubicTo(x1, y1, x2, y2, x, y):
					out.add('C${n(x1)} ${n(y1)} ${n(x2)} ${n(y2)} ${n(x)} ${n(y)}');
				case QuadTo(x1, y1, x, y):
					out.add('Q${n(x1)} ${n(y1)} ${n(x)} ${n(y)}');
				case ArcTo(rx, ry, rotation, large, sweep, x, y):
					out.add('A${n(rx)} ${n(ry)} ${n(rotation)} ${large ? 1 : 0} ${sweep ? 1 : 0} ${n(x)} ${n(y)}');
				case Close:
					out.add("Z");
			}
		}
		return out.toString();
	}

	/** A number as SVG writes it: at most four decimals, an integer without a point. **/
	public static function n(v:Float):String {
		var r = Math.fround(v * 10000) / 10000;
		return Math.abs(r) < 1e9 && r == Std.int(r) ? Std.string(Std.int(r)) : Std.string(r);
	}
}

/** A cursor over path data. **/
private class PathReader {
	final d:String;
	var i = 0;
	final out:Array<PathCommand> = [];
	// The current point, the start of the subpath, and the last control point of a curve.
	var x = 0.0;
	var y = 0.0;
	var startX = 0.0;
	var startY = 0.0;
	var lastCubic:Null<{x:Float, y:Float}> = null;
	var lastQuad:Null<{x:Float, y:Float}> = null;

	public function new(d:String) {
		this.d = d;
	}

	public function read():Array<PathCommand> {
		skip();
		if (i < d.length && d.charAt(i) != "M" && d.charAt(i) != "m")
			fail("a path starts with M");
		var command = "";
		while (true) {
			skip();
			if (i >= d.length)
				break;
			var c = d.charAt(i);
			if (isCommand(c)) {
				command = c;
				i++;
			} else if (command == "" || command == "Z" || command == "z") {
				fail('expected a command, not "$c"');
			}
			step(command);
			// After M, further coordinate pairs are lines.
			if (command == "M")
				command = "L";
			else if (command == "m")
				command = "l";
		}
		return out;
	}

	function step(command:String):Void {
		var relative = command.toLowerCase() == command;
		var ox = relative ? x : 0.0;
		var oy = relative ? y : 0.0;
		var cubic:Null<{x:Float, y:Float}> = null;
		var quad:Null<{x:Float, y:Float}> = null;
		switch command.toUpperCase() {
			case "M":
				x = ox + number();
				y = oy + number();
				startX = x;
				startY = y;
				out.push(MoveTo(x, y));
			case "L":
				x = ox + number();
				y = oy + number();
				out.push(LineTo(x, y));
			case "H":
				x = ox + number();
				out.push(LineTo(x, y));
			case "V":
				y = oy + number();
				out.push(LineTo(x, y));
			case "C":
				var x1 = ox + number(), y1 = oy + number();
				var x2 = ox + number(), y2 = oy + number();
				x = ox + number();
				y = oy + number();
				out.push(CubicTo(x1, y1, x2, y2, x, y));
				cubic = {x: x2, y: y2};
			case "S":
				// The first control point reflects the last curve's second one.
				var x1 = lastCubic == null ? x : 2 * x - lastCubic.x;
				var y1 = lastCubic == null ? y : 2 * y - lastCubic.y;
				var x2 = ox + number(), y2 = oy + number();
				x = ox + number();
				y = oy + number();
				out.push(CubicTo(x1, y1, x2, y2, x, y));
				cubic = {x: x2, y: y2};
			case "Q":
				var x1 = ox + number(), y1 = oy + number();
				x = ox + number();
				y = oy + number();
				out.push(QuadTo(x1, y1, x, y));
				quad = {x: x1, y: y1};
			case "T":
				var x1 = lastQuad == null ? x : 2 * x - lastQuad.x;
				var y1 = lastQuad == null ? y : 2 * y - lastQuad.y;
				x = ox + number();
				y = oy + number();
				out.push(QuadTo(x1, y1, x, y));
				quad = {x: x1, y: y1};
			case "A":
				var rx = Math.abs(number()), ry = Math.abs(number());
				var rotation = number();
				var large = flag(), sweep = flag();
				x = ox + number();
				y = oy + number();
				out.push(ArcTo(rx, ry, rotation, large, sweep, x, y));
			case "Z":
				x = startX;
				y = startY;
				out.push(Close);
			case _:
				fail('unknown command "$command"');
		}
		lastCubic = cubic;
		lastQuad = quad;
	}

	static inline function isCommand(c:String):Bool
		return "MmLlHhVvCcSsQqTtAaZz".indexOf(c) >= 0;

	/** Whitespace and at most one comma. **/
	function skip():Void {
		var comma = false;
		while (i < d.length) {
			var c = d.charCodeAt(i);
			if (c == " ".code || c == "\t".code || c == "\n".code || c == "\r".code || c == 0x0C) {
				i++;
			} else if (c == ",".code && !comma) {
				comma = true;
				i++;
			} else {
				break;
			}
		}
	}

	/** An arc flag, a lone 0 or 1, which may run straight into the next number. **/
	function flag():Bool {
		skip();
		var c = i < d.length ? d.charAt(i) : "";
		if (c != "0" && c != "1")
			fail("an arc flag is 0 or 1");
		i++;
		return c == "1";
	}

	function number():Float {
		skip();
		var start = i;
		if (i < d.length && (d.charAt(i) == "+" || d.charAt(i) == "-"))
			i++;
		var digits = 0;
		while (i < d.length && isDigit(d.charCodeAt(i))) {
			i++;
			digits++;
		}
		if (i < d.length && d.charAt(i) == ".") {
			i++;
			while (i < d.length && isDigit(d.charCodeAt(i))) {
				i++;
				digits++;
			}
		}
		if (digits == 0)
			fail(i >= d.length ? "the path ends in the middle of a command" : 'expected a number at "${d.substr(start, 8)}"');
		if (i < d.length && (d.charAt(i) == "e" || d.charAt(i) == "E")) {
			var mark = i;
			i++;
			if (i < d.length && (d.charAt(i) == "+" || d.charAt(i) == "-"))
				i++;
			if (i < d.length && isDigit(d.charCodeAt(i))) {
				while (i < d.length && isDigit(d.charCodeAt(i)))
					i++;
			} else {
				i = mark;
			}
		}
		return Std.parseFloat(d.substring(start, i));
	}

	static inline function isDigit(c:Int):Bool
		return c >= "0".code && c <= "9".code;

	function fail(message:String):Dynamic {
		throw new SvgError('path data, at ${i}: $message');
	}
}
