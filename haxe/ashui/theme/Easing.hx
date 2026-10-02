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
		Progress at `t`, clamped to 0..1. A cubic bézier is approximated as
		Blinc approximates it: its y polynomial at parameter `t`, ignoring
		x1 and x2.
	**/
	public static function evaluate(easing:Easing, t:Float):Float {
		var t = Math.max(0, Math.min(1, t));
		return switch easing {
			case Linear: t;
			case EaseIn: t * t;
			case EaseOut: 1 - (1 - t) * (1 - t);
			case EaseInOut: t < 0.5 ? 2 * t * t : 1 - Math.pow(-2 * t + 2, 2) / 2;
			case CubicBezier(_, y1, _, y2):
				var mt = 1 - t;
				3 * mt * mt * t * y1 + 3 * mt * t * t * y2 + t * t * t;
		}
	}
}
