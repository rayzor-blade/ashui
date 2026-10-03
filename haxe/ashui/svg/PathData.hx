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

	/**
		The subpaths of `commands` as closed rings of points, `[x0, y0, x1,
		y1, …]`, the last point the first again: curves and arcs cut into
		straight steps of about `step` units.
	**/
	public static function flatten(commands:Array<PathCommand>, step = 1.0):Array<Array<Float>> {
		var rings:Array<Array<Float>> = [];
		var ring:Array<Float> = [];
		var x = 0.0, y = 0.0, startX = 0.0, startY = 0.0;
		function close() {
			if (ring.length >= 6) {
				if (ring[0] != ring[ring.length - 2] || ring[1] != ring[ring.length - 1]) {
					ring.push(ring[0]);
					ring.push(ring[1]);
				}
				rings.push(ring);
			}
			ring = [];
		}
		function to(nx:Float, ny:Float) {
			if (ring.length == 0) {
				ring.push(x);
				ring.push(y);
			}
			ring.push(nx);
			ring.push(ny);
			x = nx;
			y = ny;
		}
		function steps(length:Float):Int
			return Std.int(Math.max(1, Math.min(256, Math.ceil(length / step))));
		for (c in commands)
			switch c {
				case MoveTo(nx, ny):
					close();
					x = startX = nx;
					y = startY = ny;
				case LineTo(nx, ny):
					to(nx, ny);
				case QuadTo(x1, y1, nx, ny):
					var x0 = x, y0 = y;
					var n = steps(Math.sqrt((x1 - x0) * (x1 - x0) + (y1 - y0) * (y1 - y0)) + Math.sqrt((nx - x1) * (nx - x1) + (ny - y1) * (ny - y1)));
					for (k in 1...n + 1) {
						var t = k / n, u = 1 - t;
						to(u * u * x0 + 2 * u * t * x1 + t * t * nx, u * u * y0 + 2 * u * t * y1 + t * t * ny);
					}
				case CubicTo(x1, y1, x2, y2, nx, ny):
					var x0 = x, y0 = y;
					function len(ax:Float, ay:Float, bx:Float, by:Float)
						return Math.sqrt((bx - ax) * (bx - ax) + (by - ay) * (by - ay));
					var n = steps(len(x0, y0, x1, y1) + len(x1, y1, x2, y2) + len(x2, y2, nx, ny));
					for (k in 1...n + 1) {
						var t = k / n, u = 1 - t;
						to(u * u * u * x0 + 3 * u * u * t * x1 + 3 * u * t * t * x2 + t * t * t * nx,
							u * u * u * y0 + 3 * u * u * t * y1 + 3 * u * t * t * y2 + t * t * t * ny);
					}
				case ArcTo(rx, ry, rotation, largeArc, sweep, nx, ny):
					arc(x, y, rx, ry, rotation, largeArc, sweep, nx, ny, step, to);
				case Close:
					to(startX, startY);
					close();
					x = startX;
					y = startY;
			}
		close();
		return rings;
	}

	/** Calls `to` along an SVG arc from `(x1, y1)` to `(x2, y2)`, by its centre form (SVG 1.1, F.6.5). **/
	static function arc(x1:Float, y1:Float, rx:Float, ry:Float, rotation:Float, largeArc:Bool, sweep:Bool, x2:Float, y2:Float, step:Float,
			to:(Float, Float) -> Void):Void {
		rx = Math.abs(rx);
		ry = Math.abs(ry);
		if (rx == 0 || ry == 0 || (x1 == x2 && y1 == y2)) {
			to(x2, y2);
			return;
		}
		var phi = rotation * Math.PI / 180, cos = Math.cos(phi), sin = Math.sin(phi);
		var dx = (x1 - x2) / 2, dy = (y1 - y2) / 2;
		var px = cos * dx + sin * dy, py = -sin * dx + cos * dy;
		// Radii too small to reach are scaled up until they just do.
		var lambda = px * px / (rx * rx) + py * py / (ry * ry);
		if (lambda > 1) {
			rx *= Math.sqrt(lambda);
			ry *= Math.sqrt(lambda);
		}
		var num = rx * rx * ry * ry - rx * rx * py * py - ry * ry * px * px;
		var den = rx * rx * py * py + ry * ry * px * px;
		var coef = (largeArc == sweep ? -1 : 1) * Math.sqrt(Math.max(0, num / den));
		var cpx = coef * rx * py / ry, cpy = -coef * ry * px / rx;
		var cx = cos * cpx - sin * cpy + (x1 + x2) / 2, cy = sin * cpx + cos * cpy + (y1 + y2) / 2;
		function angle(ux:Float, uy:Float, vx:Float, vy:Float)
			return Math.atan2(ux * vy - uy * vx, ux * vx + uy * vy);
		var start = angle(1, 0, (px - cpx) / rx, (py - cpy) / ry);
		var sweepAngle = angle((px - cpx) / rx, (py - cpy) / ry, (-px - cpx) / rx, (-py - cpy) / ry);
		if (!sweep && sweepAngle > 0)
			sweepAngle -= 2 * Math.PI;
		else if (sweep && sweepAngle < 0)
			sweepAngle += 2 * Math.PI;
		var n = Std.int(Math.max(1, Math.min(256, Math.ceil(Math.abs(sweepAngle) * Math.max(rx, ry) / step))));
		for (k in 1...n + 1) {
			var t = start + sweepAngle * k / n;
			to(cos * rx * Math.cos(t) - sin * ry * Math.sin(t) + cx, sin * rx * Math.cos(t) + cos * ry * Math.sin(t) + cy);
		}
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
