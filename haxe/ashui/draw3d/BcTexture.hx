package ashui.draw3d;

import haxe.io.Bytes;

/**
	A bitmap block-compressed for a mesh: every mip level of it as a role reads it, in the formats `BcEncoder` makes. It reads
	the bitmap's pixels, so it needs the bitmap's natives, which `BcEncoder` and `BcImage` do not.
**/
class BcTexture {
	/** Pixels each level is resampled into on the way: reused from level to level and image to image, by one thread at a time. **/
	static var work:Null<Bytes> = null;

	/**
		`bitmap` read as `role` reads it, every level of it block-compressed: BC1 for colour (BC3 where it has alpha) and for
		data, BC4 for occlusion, BC5 for a normal map. The levels are the bitmap's sides halved down to one pixel, each resampled
		from the image itself, not from the level above. What a mesh texture is uploaded from, as the program runs on a worker or
		ahead of time with the `bcpack` tool, whose files `BcImage` reads. Its sides should be multiples of 4.
	**/
	public static function of(bitmap:ashui.types.Bitmap, role:TextureRole):BcImage {
		var w = bitmap.width, h = bitmap.height, slot = bitmap.slot;
		if (work == null || work.length < w * h * 4)
			work = Bytes.alloc(w * h * 4);
		var px = work, out = [], format = BcImage.BC4;
		for (level in 0...BcImage.levelCount(w, h)) {
			var lw = BcImage.levelSize(w, level), lh = BcImage.levelSize(h, level);
			@:privateAccess ashui.core.externs.BitmapNative.blinc_bitmap_resample(slot, lw, lh, (Fill : ashui.types.Brush.ImageFit), px);
			switch role {
				case Color:
					// Alpha is decided by the sharpest level, so every level is the same format.
					if (level == 0)
						format = BcEncoder.opaque(px, lw * lh) ? BcImage.BC1_SRGB : BcImage.BC3_SRGB;
					out.push(format == BcImage.BC1_SRGB ? BcEncoder.bc1(px, lw, lh) : BcEncoder.bc3(px, lw, lh));
				case Data:
					format = BcImage.BC1;
					out.push(BcEncoder.bc1(px, lw, lh));
				case Occlusion:
					format = BcImage.BC4;
					out.push(BcEncoder.bc4(px, lw, lh, 0));
				case Normal:
					format = BcImage.BC5;
					out.push(BcEncoder.bc5(px, lw, lh));
			}
		}
		return new BcImage(w, h, format, out);
	}
}
