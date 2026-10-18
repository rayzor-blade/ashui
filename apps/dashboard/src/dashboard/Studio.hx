package dashboard;

import ashui.canvaskit.Environment;
import ashui.math.Vec3;

/** The light the car stands in. **/
class Studio {
	/**
		A product photographer's studio as light from every direction: a
		broad softbox overhead, a long strip light low on either side that
		lays a highlight along the car's flanks, and walls falling softly to
		the floor. `dark` gives a dark studio lit only by the softbox and the
		strips.
	**/
	public static function environment(dark:Bool):Environment
		return Environment.fromFunction(128, d -> {
			var wall = dark ? 0.18 : 0.6, floor = dark ? 0.05 : 0.2, top = dark ? 0.36 : 0.9;
			var base = floor + (wall - floor) * smoothstep(-0.95, 0.25, d.y);
			base += (top - base) * smoothstep(0.0, 1.0, d.y);
			var softbox = (dark ? 1.4 : 1.1) * smoothstep(0.45, 1.0, d.y);
			var strip = (dark ? 1.0 : 0.8) * Math.exp(-Math.pow((d.y - 0.16) / 0.1, 2)) * smoothstep(0.2, 0.95, Math.abs(d.x));
			var v = base + softbox + strip;
			new Vec3(v, v, v * (dark ? 1.04 : 1.0));
		});

	static inline function smoothstep(a:Float, b:Float, t:Float):Float {
		var c = (t - a) / (b - a);
		c = c < 0 ? 0 : c > 1 ? 1 : c;
		return c * c * (3 - 2 * c);
	}
}
