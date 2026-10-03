package ashui.core.render;

import ashui.core.externs.SvgNative;
import ashui.layout.DisplayList;
import ashui.svg.SvgDocument;

/**
	Gives each image record of a display list its rect in the image atlas,
	rasterizing the image there first at the size it covers on screen. Sizes
	are bucketed at twelve steps per doubling of scale, as text is, so a
	zoom reuses rasterizations instead of making one a frame.
**/
class Images {
	static inline var STEPS_PER_OCTAVE = 12;
	/** The largest side an image is rasterized at; beyond it, it is magnified. **/
	static inline var MAX_SIDE = 2048;

	static inline var BOUNDS = 0;
	static inline var COLOR = 8;
	static inline var COLOR2 = 12;
	static inline var GRADIENT = 40;
	static inline var FILL = 45;

	/** Resolves `list`'s image records against `atlas`, emptying it once if they do not all fit. **/
	public static function resolve(list:DisplayList, atlas:ImageAtlas):Void {
		if (!resolveAll(list, atlas)) {
			atlas.reset();
			resolveAll(list, atlas);
		}
	}

	static function resolveAll(list:DisplayList, atlas:ImageAtlas):Bool {
		var fitted = true;
		for (r in 0...list.count) {
			if (list.kind(r) != DisplayList.PRIM_IMAGE)
				continue;
			var slot = Std.int(list.get(r, GRADIENT));
			var onScreen = list.get(r, GRADIENT + 1);
			var doc = SvgDocument.get(slot);
			var rect = doc == null ? null : rasterized(doc, list, r, onScreen, atlas);
			if (rect == null) {
				if (doc != null)
					fitted = false;
				// Nothing to draw: no colour, no opacity.
				list.set(r, COLOR + 3, 0);
				list.set(r, COLOR2 + 3, 0);
				continue;
			}
			list.set(r, GRADIENT, rect.x);
			list.set(r, GRADIENT + 1, rect.y);
			list.set(r, GRADIENT + 2, rect.x + rect.width);
			list.set(r, GRADIENT + 3, rect.y + rect.height);
			list.set(r, FILL, doc.mask ? 0 : 1);
		}
		return fitted;
	}

	static function rasterized(doc:SvgDocument, list:DisplayList, r:Int, onScreen:Float, atlas:ImageAtlas):Null<ImageAtlas.Rect> {
		var scale = bucket(onScreen);
		var width = side(list.get(r, BOUNDS + 2) * scale);
		var height = side(list.get(r, BOUNDS + 3) * scale);
		var key = '${doc.id}:${width}x$height';
		// A mask is rasterized white and tinted when drawn; a colour image bakes in its currentColor.
		var color = "#ffffff";
		if (!doc.mask) {
			color = "#" + StringTools.hex(channel(list.get(r, COLOR)) << 16 | channel(list.get(r, COLOR + 1)) << 8 | channel(list.get(r, COLOR + 2)), 6);
			if (doc.markup.indexOf("currentColor") >= 0)
				key += color;
		}
		return atlas.get(key, width, height, pixels -> {
			var source = doc.withColor(color);
			SvgNative.blinc_svg_rasterize(ashui.core.Utf8.encode(source), width, height, pixels.getData());
		});
	}

	static function bucket(onScreen:Float):Float {
		if (!(onScreen > 0))
			return 1;
		return Math.pow(2, Math.round(Math.log(onScreen) / Math.log(2) * STEPS_PER_OCTAVE) / STEPS_PER_OCTAVE);
	}

	static inline function side(v:Float):Int
		return Std.int(Math.max(1, Math.min(MAX_SIDE, Math.ceil(v - 0.01))));

	static inline function channel(v:Float):Int
		return Std.int(Math.max(0, Math.min(255, Math.round(v * 255))));
}
