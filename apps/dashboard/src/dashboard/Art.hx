package dashboard;

import ashui.draw.DrawContext;
import ashui.draw.Stroke;
import ashui.types.Brush;

/** A track's cover, drawn: a gradient of its hue with rings round a disc, as a vinyl's label. **/
class Art {
	/** A colour from hue (degrees), saturation and lightness (0 to 1), as 0xRRGGBB. **/
	public static function hsl(h:Float, s:Float, l:Float):Int {
		h = ((h % 360) + 360) % 360;
		var c = (1 - Math.abs(2 * l - 1)) * s, x = c * (1 - Math.abs((h / 60) % 2 - 1)), m = l - c / 2;
		var r = 0.0, g = 0.0, b = 0.0;
		if (h < 60) {
			r = c;
			g = x;
		} else if (h < 120) {
			r = x;
			g = c;
		} else if (h < 180) {
			g = c;
			b = x;
		} else if (h < 240) {
			g = x;
			b = c;
		} else if (h < 300) {
			r = x;
			b = c;
		} else {
			r = c;
			b = x;
		}
		return (Math.round((r + m) * 255) << 16) | (Math.round((g + m) * 255) << 8) | Math.round((b + m) * 255);
	}

	/** The art of a track of `hue`, `size` square. **/
	public static function draw(size:Float, hue:Int):DrawContext->Void
		return ctx -> {
			var k = size / 56;
			ctx.pushClipRect(0, 0, size, size, 12 * k);
			ctx.fillRect(0, 0, size, size, Brush.linear(0, 0, size, size).stop(0, hsl(hue, 0.7, 0.42)).stop(0.55, hsl(hue + 45, 0.72, 0.5)).stop(1, hsl(hue + 85, 0.8, 0.58)));
			for (i in 0...4)
				ctx.strokeCircle(42 * k, 44 * k, (10 + i * 9) * k, new Stroke(1.2 * k), Brush.solid(0xffffff, 0.35 - i * 0.07));
			ctx.fillCircle(42 * k, 44 * k, 6 * k, Brush.solid(0xffffff, 0.85));
			ctx.popClip();
		};
}
