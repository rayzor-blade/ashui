package ashui.theme;

/** A timing curve of the theme. **/
enum Easing {
	Linear;
	EaseIn;
	EaseOut;
	EaseInOut;
	CubicBezier(x1:Float, y1:Float, x2:Float, y2:Float);
}

class EasingTools {
	/**
		Progress at `t`, clamped to 0..1. A cubic bézier is solved for the x
		at `t` and gives the y there, as CSS's `cubic-bezier` does.
	**/
	public static function evaluate(easing:Easing, t:Float):Float {
		var t = Math.max(0, Math.min(1, t));
		return switch easing {
			case Linear: t;
			case EaseIn: t * t;
			case EaseOut: 1 - (1 - t) * (1 - t);
			case EaseInOut: t < 0.5 ? 2 * t * t : 1 - Math.pow(-2 * t + 2, 2) / 2;
			case CubicBezier(x1, y1, x2, y2): bezier(x1, y1, x2, y2, t);
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
