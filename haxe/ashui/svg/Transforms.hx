package ashui.svg;

/**
	SVG `transform` lists: `translate(10 4) rotate(45 12 12) scale(2)` and
	`matrix`, `skewX`, `skewY`, applied right to left as SVG does. A result
	`[a, b, c, d, e, f]` maps `(x, y)` to `(a·x + c·y + e, b·x + d·y + f)`.
**/
class Transforms {
	public static function parse(v:String):Array<Float> {
		var m = [1.0, 0, 0, 1, 0, 0];
		var fn = ~/^\s*,?\s*([a-zA-Z]+)\s*\(([^)]*)\)/;
		var rest = v;
		while (fn.match(rest)) {
			var args = SvgParser.numbers(fn.matched(2), "transform");
			m = multiply(m, one(fn.matched(1), args, v));
			rest = fn.matchedRight();
		}
		if (StringTools.trim(rest) != "")
			throw new SvgError('transform "$v" is not a list of transform functions');
		return m;
	}

	static function one(name:String, a:Array<Float>, v:String):Array<Float> {
		function need(counts:Array<Int>)
			if (counts.indexOf(a.length) < 0)
				throw new SvgError('transform "$v": $name takes ${counts.join(" or ")} numbers');
		inline function rad(deg:Float)
			return deg * Math.PI / 180;
		return switch name {
			case "matrix":
				need([6]);
				a;
			case "translate":
				need([1, 2]);
				[1, 0, 0, 1, a[0], a.length > 1 ? a[1] : 0];
			case "scale":
				need([1, 2]);
				[a[0], 0, 0, a.length > 1 ? a[1] : a[0], 0, 0];
			case "rotate":
				need([1, 3]);
				var c = Math.cos(rad(a[0])), s = Math.sin(rad(a[0]));
				var r = [c, s, -s, c, 0, 0];
				a.length == 3 ? multiply(multiply([1, 0, 0, 1, a[1], a[2]], r), [1, 0, 0, 1, -a[1], -a[2]]) : r;
			case "skewX":
				need([1]);
				[1, 0, Math.tan(rad(a[0])), 1, 0, 0];
			case "skewY":
				need([1]);
				[1, Math.tan(rad(a[0])), 0, 1, 0, 0];
			case _:
				throw new SvgError('transform "$v": unknown function $name');
		}
	}

	/** `p` after `q`: a point goes through `q` first. **/
	public static function multiply(p:Array<Float>, q:Array<Float>):Array<Float> {
		return [
			p[0] * q[0] + p[2] * q[1],
			p[1] * q[0] + p[3] * q[1],
			p[0] * q[2] + p[2] * q[3],
			p[1] * q[2] + p[3] * q[3],
			p[0] * q[4] + p[2] * q[5] + p[4],
			p[1] * q[4] + p[3] * q[5] + p[5]
		];
	}
}
