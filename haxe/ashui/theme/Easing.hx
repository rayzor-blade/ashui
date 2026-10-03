package ashui.theme;

/** A timing curve of the theme. **/
enum Easing {
	Linear;
	EaseIn;
	EaseOut;
	EaseInOut;
	CubicBezier(x1:Float, y1:Float, x2:Float, y2:Float);
	/** CSS's `steps()`: `count` equal jumps, the first at the start when `jumpStart`, else at the end of the first step. **/
	Steps(count:Int, jumpStart:Bool);
}

/** Reads an `Easing`: its progress at a time, and its control points. **/
class EasingTools {
	/**
		Progress at `t`, which is clamped to 0..1: the curve's y where its x is
		`t`, as CSS's `cubic-bezier` gives it. The result is not clamped, so a
		spring curve overshoots past 1 partway through.
	**/
	public static function evaluate(easing:Easing, t:Float):Float {
		var t = Math.max(0, Math.min(1, t));
		switch easing {
			case Steps(n, start):
				return t >= 1 ? 1 : Math.min(1, (start ? Math.ffloor(t * n) + 1 : Math.ffloor(t * n)) / n);
			case _:
		}
		return switch controlPoints(easing) {
			case null: t;
			case p: bezier(p[0], p[1], p[2], p[3], t);
		}
	}

	/**
		The cubic bézier the curve is, as CSS writes it: the named curves are
		CSS's `ease-in`, `ease-out` and `ease-in-out`. Null for linear. The
		theme's CSS variables and `evaluate` both read it, so they agree.
	**/
	public static function controlPoints(easing:Easing):Null<Array<Float>> {
		return switch easing {
			case Linear: null;
			case EaseIn: [0.4, 0, 1, 1];
			case EaseOut: [0, 0, 0.2, 1];
			case EaseInOut: [0.4, 0, 0.2, 1];
			case CubicBezier(x1, y1, x2, y2): [x1, y1, x2, y2];
			case Steps(_, _): null;
		}
	}

	/** The bézier through (0,0), (x1,y1), (x2,y2), (1,1) at x: Newton steps, then bisection if they stall. **/
	static function bezier(x1:Float, y1:Float, x2:Float, y2:Float, x:Float):Float {
		inline function at(a:Float, b:Float, s:Float):Float {
			var m = 1 - s;
			return 3 * m * m * s * a + 3 * m * s * s * b + s * s * s;
		}
		inline function slope(a:Float, b:Float, s:Float):Float {
			var m = 1 - s;
			return 3 * m * m * a + 6 * m * s * (b - a) + 3 * s * s * (1 - b);
		}
		var s = x;
		for (_ in 0...8) {
			var error = at(x1, x2, s) - x;
			if (Math.abs(error) < 1e-7)
				return at(y1, y2, s);
			var d = slope(x1, x2, s);
			if (Math.abs(d) < 1e-6)
				break;
			s -= error / d;
		}
		var lo = 0.0, hi = 1.0;
		s = x;
		for (_ in 0...40) {
			var value = at(x1, x2, s);
			if (Math.abs(value - x) < 1e-7)
				break;
			if (value < x)
				lo = s;
			else
				hi = s;
			s = (lo + hi) / 2;
		}
		return at(y1, y2, s);
	}
}
