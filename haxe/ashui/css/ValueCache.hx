package ashui.css;

import ashui.types.Brush;
import ashui.types.Color;
import ashui.types.CornerRadius;

/**
	The style values a stylesheet writes, shared between elements: each is a native handle that costs the collector a
	pressure charge, and a rule that styles a thousand elements writes the same few values to all of them. A value is
	immutable once made and a constant bound to a node is copied by the engine, so one object may serve any number
	of elements. Each table is dropped when it holds `LIMIT` entries, so values from an app that makes endless
	different ones are not kept for good.
**/
class ValueCache {
	static inline var LIMIT = 4096;

	static var colors = new Map<String, Color>();
	static var solids = new Map<String, Brush>();
	static var radii = new Map<String, CornerRadius>();

	public static function color(rgb:Int, alpha:Float):Color {
		var key = rgb + ":" + alpha;
		var found = colors.get(key);
		if (found == null) {
			if (Lambda.count(colors) >= LIMIT)
				colors = new Map();
			colors.set(key, found = new Color(rgb, alpha));
		}
		return found;
	}

	public static function solid(rgb:Int, alpha:Float):Brush {
		var key = rgb + ":" + alpha;
		var found = solids.get(key);
		if (found == null) {
			if (Lambda.count(solids) >= LIMIT)
				solids = new Map();
			solids.set(key, found = Brush.solid(rgb, alpha));
		}
		return found;
	}

	public static function radius(topLeft:Float, topRight:Float, bottomRight:Float, bottomLeft:Float):CornerRadius {
		var key = topLeft + ":" + topRight + ":" + bottomRight + ":" + bottomLeft;
		var found = radii.get(key);
		if (found == null) {
			if (Lambda.count(radii) >= LIMIT)
				radii = new Map();
			radii.set(key, found = new CornerRadius(topLeft, topRight, bottomRight, bottomLeft));
		}
		return found;
	}
}
