package ashui.theme;

/**
	Controls how the theme smooths rounded corners into squircles.

	- `cornerSmoothing` blends from a circle (0) toward `cornerExponent` (1).
	- `cornerExponent` sets the target superellipse exponent. A circle uses 2.
	- `smoothingThreshold` is the minimum corner radius to smooth, in pixels.

	Zero smoothing or an infinite threshold disables the effect. An explicit
	node corner shape takes precedence, except for an unlocked round shape.
	See `ashui.types.CornerShape`.
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

	/** `token`'s value. **/
	public function get(token:ShapeToken):Float {
		return switch token {
			case CornerSmoothing: cornerSmoothing;
			case CornerExponent: cornerExponent;
			case SmoothingThreshold: smoothingThreshold;
		}
	}

	/** Whether no corner is smoothed. **/
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

	/** Interpolates with `t` clamped to 0–1. If one threshold is infinite, uses the finite threshold. **/
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
		return cornerSmoothing == other.cornerSmoothing
			&& cornerExponent == other.cornerExponent
			&& smoothingThreshold == other.smoothingThreshold;
	}
}
