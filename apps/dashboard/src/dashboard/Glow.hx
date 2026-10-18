package dashboard;

import ashui.types.Bitmap;

/** A disc of light, white, its alpha falling smoothly from the centre to nothing at the edge. **/
class Glow {
	static final made = new Map<Int, Bitmap>();

	/** One `size` pixels across. **/
	public static function of(size:Int):Bitmap {
		var known = made.get(size);
		if (known != null)
			return known;
		var px = haxe.io.Bytes.alloc(size * size * 4);
		for (y in 0...size)
			for (x in 0...size) {
				var dx = (x + 0.5) / size * 2 - 1, dy = (y + 0.5) / size * 2 - 1;
				var r = Math.min(1, Math.sqrt(dx * dx + dy * dy));
				var o = (y * size + x) * 4;
				px.fill(o, 3, 255);
				px.set(o + 3, Std.int(Math.pow(1 - r * r * (3 - 2 * r), 1.6) * 255));
			}
		var bitmap = Bitmap.fromBytes(ashui.core.render.Png.encode(size, size, px));
		made.set(size, bitmap);
		return bitmap;
	}
}
