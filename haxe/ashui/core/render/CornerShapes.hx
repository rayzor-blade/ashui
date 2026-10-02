package ashui.core.render;

import ashui.theme.ShapeTokens;

/** The corner shapes boxes are drawn with: each corner's `n`, top-left first. **/
class CornerShapes {
	public static final ROUND:Array<Float> = [1, 1, 1, 1];

	public static function isRound(shape:Array<Float>):Bool {
		for (n in shape)
			if (Math.abs(n - 1) >= 0.001)
				return false;
		return true;
	}

	/**
		The shape to draw a box with, as Blinc's paint walk decides it. An
		explicit shape, or a locked one, wins. Otherwise a theme with
		smoothing on gives each corner its squircle `n`, except corners under
		the threshold, corners near a full circle (at least 99% of
		`radiusFull` or 90% of half the shorter side) and pills, which stay
		round so they do not wobble.
	**/
	public static function resolve(explicit:Array<Float>, radii:Array<Float>, width:Float, height:Float, theme:ShapeTokens, radiusFull:Float,
			locked:Bool):Array<Float> {
		if (locked || !isRound(explicit))
			return explicit;
		if (theme.isOff())
			return ROUND;
		var halfShort = Math.min(width, height) * 0.5;
		var pill = halfShort > 0 && radii[0] >= halfShort - 0.5 && radii[1] >= halfShort - 0.5 && radii[2] >= halfShort - 0.5
			&& radii[3] >= halfShort - 0.5;
		if (pill)
			return ROUND;
		var n = theme.effectiveCornerN();
		var threshold = theme.smoothingThreshold;
		var fullCutoff = radiusFull * 0.99;
		var nearFull = halfShort * 0.90;
		return [for (r in radii) r >= fullCutoff || r >= nearFull || r < threshold ? 1 : n];
	}
}
