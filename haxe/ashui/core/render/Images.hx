package ashui.core.render;

import ashui.core.externs.SvgNative;
import ashui.layout.DisplayList;
import ashui.svg.SvgDocument;

@:noCompletion typedef ResolvedImage = {
	var record:Int;
	var rect:Null<ImageAtlas.Rect>;
	var mode:Int;
	var x:Float;
	var y:Float;
	var width:Float;
	var height:Float;
	var tiled:Bool;
}

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
	static inline var MAPPING = 4;
	static inline var COLOR = 8;
	static inline var COLOR2 = 12;
	static inline var GRADIENT = 40;
	static inline var FILL = 45;

	/** Resolves `list`'s image records against `atlas`, emptying it once if they do not all fit. **/
	public static function resolve(list:DisplayList, atlas:ImageAtlas):Void {
		if (!prepare(list, atlas)) {
			atlas.reset();
			prepare(list, atlas);
		}
		for (i in 0...atlas.prepared) {
			var image = atlas.resolving[i], r = image.record, rect = image.rect;
			if (rect == null) {
				list.set(r, COLOR + 3, 0);
				list.set(r, COLOR2 + 3, 0);
				continue;
			}
			list.set(r, GRADIENT, rect.x);
			list.set(r, GRADIENT + 1, rect.y);
			list.set(r, GRADIENT + 2, rect.x + rect.width);
			list.set(r, GRADIENT + 3, rect.y + rect.height);
			list.set(r, FILL, image.mode);
			if (image.mode == 3) {
				list.set(r, MAPPING, image.x); list.set(r, MAPPING + 1, image.y);
				list.set(r, MAPPING + 2, image.width); list.set(r, MAPPING + 3, image.height);
				list.set(r, COLOR2 + 2, image.tiled ? 1 : 0);
			} else if (image.mode == 2) {
				list.set(r, COLOR2, image.width); list.set(r, COLOR2 + 1, image.height);
			}
		}
	}

	static function prepare(list:DisplayList, atlas:ImageAtlas):Bool {
		var fitted = true;
		atlas.prepared = 0;
		for (r in 0...list.count) {
			if (list.kind(r) != DisplayList.PRIM_IMAGE) continue;
			if (atlas.prepared == atlas.resolving.length)
				atlas.resolving.push({record: 0, rect: null, mode: 0, x: 0, y: 0, width: 0, height: 0, tiled: false});
			var image = atlas.resolving[atlas.prepared++];
			image.record = r;
			var slot = Std.int(list.get(r, GRADIENT));
			var onScreen = list.get(r, GRADIENT + 1);
			var bitmap = slot >= ashui.types.Bitmap.BASE;
			var mapped = bitmap && list.get(r, FILL) == 3;
			var doc = bitmap ? null : SvgDocument.get(slot);
			var tiled = bitmap && ((slot - ashui.types.Bitmap.BASE) & 3) == ashui.types.Brush.ImageFit.Tile;
			image.mode = doc != null && doc.mask ? 0 : mapped ? 3 : tiled ? 2 : 1;
			image.rect = bitmap ? mapped ? positioned(slot - ashui.types.Bitmap.BASE, list, r, onScreen, atlas, image)
				: resampled(slot - ashui.types.Bitmap.BASE, list, r, onScreen, atlas, image)
				: doc == null ? null : rasterized(doc, list, r, onScreen, atlas);
			if (image.rect == null && (doc != null || bitmap)) fitted = false;
		}
		return fitted;
	}

	/** A positioned bitmap uses a shared whole-image atlas entry; moving it never rerasterizes it. **/
	static function positioned(code:Int, list:DisplayList, r:Int, onScreen:Float, atlas:ImageAtlas, image:ResolvedImage):Null<ImageAtlas.Rect> {
		var slot = code >> 2;
		var sw = ashui.core.externs.BitmapNative.blinc_bitmap_size(slot, false);
		var sh = ashui.core.externs.BitmapNative.blinc_bitmap_size(slot, true);
		if (sw <= 0 || sh <= 0) return null;
		var fit = Std.int(list.get(r, COLOR2 + 2));
		var w = list.get(r, BOUNDS + 2), h = list.get(r, BOUNDS + 3);
		var scale = switch fit {
			case 0: Math.max(w / sw, h / sh);
			case 1: Math.min(w / sw, h / sh);
			case 4 | 3: 1.0;
			case 5: Math.min(1, Math.min(w / sw, h / sh));
			case _: 1.0;
		};
		image.width = fit == 2 ? w : sw * scale;
		image.height = fit == 2 ? h : sh * scale;
		image.x = (w - image.width) * list.get(r, MAPPING) + list.get(r, MAPPING + 2);
		image.y = (h - image.height) * list.get(r, MAPPING + 1) + list.get(r, MAPPING + 3);
		image.tiled = fit == 3;
		return bitmap(slot, image.width, image.height, onScreen, atlas);
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

	/**
		A bitmap, `code` its slot times 4 plus its fit, resampled into the
		atlas at the size its record covers on screen. A tiled one is
		resampled once at its own size, one layout unit a pixel as CSS sizes
		images, which `COLOR2` carries for the shader to repeat.
	**/
	static function resampled(code:Int, list:DisplayList, r:Int, onScreen:Float, atlas:ImageAtlas, image:ResolvedImage):Null<ImageAtlas.Rect> {
		var scale = bucket(onScreen);
		var slot = code >> 2, fit = code & 3;
		var w = list.get(r, BOUNDS + 2), h = list.get(r, BOUNDS + 3);
		if (fit == ashui.types.Brush.ImageFit.Tile) {
			w = ashui.core.externs.BitmapNative.blinc_bitmap_size(slot, false);
			h = ashui.core.externs.BitmapNative.blinc_bitmap_size(slot, true);
			if (w <= 0 || h <= 0)
				return null;
			image.width = w;
			image.height = h;
			fit = ashui.types.Brush.ImageFit.Fill;
		}
		var width = side(w * scale);
		var height = side(h * scale);
		return atlas.get('bitmap$code:${width}x$height', width, height,
			pixels -> ashui.core.externs.BitmapNative.blinc_bitmap_resample(slot, width, height, fit, pixels.getData()));
	}

	/** Bitmap `slot`'s rect in `atlas`, resampled to fill `width` by `height` at `onScreen` target pixels a unit; null when it does not fit. **/
	public static function bitmap(slot:Int, width:Float, height:Float, onScreen:Float, atlas:ImageAtlas):Null<ImageAtlas.Rect> {
		var scale = bucket(onScreen);
		var w = side(width * scale), h = side(height * scale);
		var fill = ashui.types.Brush.ImageFit.Fill;
		return atlas.get('bitmap${slot * 4 + fill}:${w}x$h', w, h, pixels -> ashui.core.externs.BitmapNative.blinc_bitmap_resample(slot, w, h, fill, pixels.getData()));
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
