package ashui.theme;

/**
	How the theme turns rounded corners into squircles. `cornerSmoothing`
	(0 to 1) pulls the superellipse exponent from 2, a circle, toward
	`cornerExponent`; only corners of at least `smoothingThreshold` pixels
	are smoothed. Off when smoothing is 0 or the threshold is infinite.
**/
@:structInit
final class ShapeTokens {
	public static final OFF:ShapeTokens = new ShapeTokens(0, 2, Math.POSITIVE_INFINITY);

	public final cornerSmoothing:Float;
	public final cornerExponent:Float;
	public final smoothingThreshold:Float;

	public function new(cornerSmoothing:Float, cornerExponent:Float, smoothingThreshold:Float) {
		this.cornerSmoothing = F32.round(cornerSmoothing);
		this.cornerExponent = F32.round(cornerExponent);
		this.smoothingThreshold = smoothingThreshold == Math.POSITIVE_INFINITY ? smoothingThreshold : F32.round(smoothingThreshold);
	}

	public function get(token:ShapeToken):Float {
		return switch token {
			case CornerSmoothing: cornerSmoothing;
			case CornerExponent: cornerExponent;
			case SmoothingThreshold: smoothingThreshold;
		}
	}

	public function isOff():Bool {
		return cornerSmoothing <= 0.001 || !Math.isFinite(smoothingThreshold);
	}

	/** The superellipse exponent: 2 is a circle. **/
	public function effectiveMathExponent():Float {
		return F32.round(2 + (Math.max(cornerExponent, 2) - 2) * Math.max(0, Math.min(1, cornerSmoothing)));
	}

	/** The corner shape `n` the renderer takes: 1 is a circle, 2 a classic squircle. **/
	public function effectiveCornerN():Float {
		return F32.round(Math.max(Math.log(effectiveMathExponent()) / Math.log(2), 0));
	}

	/** From `from` to `to` by `t`, clamped; an infinite threshold is kept by the other end. **/
	public static function lerp(from:ShapeTokens, to:ShapeTokens, t:Float):ShapeTokens {
		var t = Math.max(0, Math.min(1, t));
		var fromFinite = Math.isFinite(from.smoothingThreshold);
		var toFinite = Math.isFinite(to.smoothingThreshold);
		var threshold = if (fromFinite && toFinite) from.smoothingThreshold + (to.smoothingThreshold - from.smoothingThreshold) * t else if (fromFinite)
			from.smoothingThreshold else if (toFinite) to.smoothingThreshold else Math.POSITIVE_INFINITY;
		return new ShapeTokens(from.cornerSmoothing + (to.cornerSmoothing - from.cornerSmoothing) * t,
			from.cornerExponent + (to.cornerExponent - from.cornerExponent) * t, threshold);
	}

	public function equals(other:ShapeTokens):Bool {
		return cornerSmoothing == other.cornerSmoothing && cornerExponent == other.cornerExponent && smoothingThreshold == other.smoothingThreshold;
	}
}
