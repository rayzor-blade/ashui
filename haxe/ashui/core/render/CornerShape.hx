package ashui.core.render;

import ashui.theme.ShapeTokens;

/**
	Each corner's superellipse `n`, top-left, top-right, bottom-right,
	bottom-left: 1 round, 2 squircle, 0 bevel, -1 scoop, 100 or more square,
	-100 or less notch. Blinc's `CornerShape`.
**/
@:structInit
final class CornerShape {
	public static final ROUND = new CornerShape(1, 1, 1, 1);
	public static final BEVEL = new CornerShape(0, 0, 0, 0);
	public static final SQUIRCLE = new CornerShape(2, 2, 2, 2);
	public static final SCOOP = new CornerShape(-1, -1, -1, -1);
	public static final NOTCH = new CornerShape(-100, -100, -100, -100);
	public static final SQUARE = new CornerShape(100, 100, 100, 100);

	public final topLeft:Float;
	public final topRight:Float;
	public final bottomRight:Float;
	public final bottomLeft:Float;

	public function new(topLeft:Float, topRight:Float, bottomRight:Float, bottomLeft:Float) {
		this.topLeft = topLeft;
		this.topRight = topRight;
		this.bottomRight = bottomRight;
		this.bottomLeft = bottomLeft;
	}

	public function isRound():Bool {
		return Math.abs(topLeft - 1) < 0.001 && Math.abs(topRight - 1) < 0.001 && Math.abs(bottomRight - 1) < 0.001
			&& Math.abs(bottomLeft - 1) < 0.001;
	}

	public function equals(other:CornerShape):Bool {
		return topLeft == other.topLeft && topRight == other.topRight && bottomRight == other.bottomRight && bottomLeft == other.bottomLeft;
	}

	/**
		The shape to draw a box with, as Blinc's paint walk decides it. An
		explicit shape, or a locked one, wins. Otherwise a theme with
		smoothing on gives each corner its squircle `n`, except corners under
		the threshold, corners near a full circle (at least 99% of
		`radiusFull` or 90% of half the shorter side) and pills, which stay
		round so they do not wobble.
	**/
	public static function resolve(explicit:CornerShape, radii:Array<Float>, width:Float, height:Float, theme:ShapeTokens, radiusFull:Float,
			locked:Bool):CornerShape {
		if (locked || !explicit.isRound())
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
		inline function corner(r:Float):Float
			return r >= fullCutoff || r >= nearFull || r < threshold ? 1 : n;
		return new CornerShape(corner(radii[0]), corner(radii[1]), corner(radii[2]), corner(radii[3]));
	}
}
