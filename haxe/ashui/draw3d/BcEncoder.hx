package ashui.draw3d;

import haxe.io.Bytes;

/**
	Block compression, as GPUs sample it directly: each 4×4 block of an
	RGBA image (four bytes a pixel, row by row) stored in 8 or 16 bytes
	rather than 64. A texture so stored takes a quarter or an eighth of
	the memory.

	- `bc1`: colour, 8 bytes a block. Two endpoint colours and, for each
	  pixel, which of four colours between them it is nearest.
	- `bc4`: one channel, 8 bytes a block. Two endpoints and eight values
	  between them.
	- `bc3`: colour with alpha, 16 bytes: alpha as `bc4`, then colour as `bc1`.
	- `bc5`: two channels, 16 bytes: red as `bc4`, then green. Normal maps,
	  whose third component is worked out from the two.

	Endpoints are each block's extremes, inset slightly, along the diagonal
	of its colour box the colours lie along; each pixel takes the nearest
	of the values between them. Images whose sides are not a multiple of 4
	repeat their last row and column to fill the blocks. With `-D ash_simd`
	on Ash, one-channel blocks are searched with ash-simd's 16-lane bytes.
**/
class BcEncoder {
	/** Colour, 8 bytes a 4×4 block. **/
	public static function bc1(rgba:Bytes, width:Int, height:Int):Bytes {
		var out = Bytes.alloc(blocks(width, height) * 8);
		var block = new haxe.ds.Vector<Int>(48);
		var o = 0;
		for (by in 0...(height + 3) >> 2)
			for (bx in 0...(width + 3) >> 2) {
				gather(rgba, width, height, bx, by, block);
				colorBlock(block, out, o);
				o += 8;
			}
		return out;
	}

	/** Colour with alpha, 16 bytes a 4×4 block. **/
	public static function bc3(rgba:Bytes, width:Int, height:Int):Bytes {
		var out = Bytes.alloc(blocks(width, height) * 16);
		var block = new haxe.ds.Vector<Int>(48);
		var channel = new haxe.ds.Vector<Int>(16);
		var o = 0;
		for (by in 0...(height + 3) >> 2)
			for (bx in 0...(width + 3) >> 2) {
				gatherChannel(rgba, width, height, bx, by, 3, channel);
				channelBlock(channel, out, o);
				gather(rgba, width, height, bx, by, block);
				colorBlock(block, out, o + 8);
				o += 16;
			}
		return out;
	}

	/** Channel `channel` (0 red, 1 green, 2 blue, 3 alpha), 8 bytes a 4×4 block. **/
	public static function bc4(rgba:Bytes, width:Int, height:Int, channel = 0):Bytes {
		var out = Bytes.alloc(blocks(width, height) * 8);
		channels(rgba, width, height, [channel], out, 8);
		return out;
	}

	/** Red then green, 16 bytes a 4×4 block. **/
	public static function bc5(rgba:Bytes, width:Int, height:Int):Bytes {
		var out = Bytes.alloc(blocks(width, height) * 16);
		channels(rgba, width, height, [0, 1], out, 16);
		return out;
	}

	/** Whether every pixel's alpha is full. **/
	public static function opaque(rgba:Bytes):Bool {
		var i = 3;
		while (i < rgba.length) {
			if (rgba.get(i) != 255)
				return false;
			i += 4;
		}
		return true;
	}

	/** 4×4 blocks to cover `width` × `height`. **/
	public static inline function blocks(width:Int, height:Int):Int
		return ((width + 3) >> 2) * ((height + 3) >> 2);

	/** Each of `which` channels, a BC4 block each, side by side in blocks `stride` bytes apart. **/
	static function channels(rgba:Bytes, width:Int, height:Int, which:Array<Int>, out:Bytes, stride:Int):Void {
		#if (ash_simd && hl)
		var slots = new hl.Bytes(64);
		#end
		var channel = new haxe.ds.Vector<Int>(16);
		var o = 0;
		for (by in 0...(height + 3) >> 2)
			for (bx in 0...(width + 3) >> 2) {
				for (k in 0...which.length) {
					#if (ash_simd && hl)
					channelBlockSimd(rgba, width, height, bx, by, which[k], slots, out, o + k * 8);
					#else
					gatherChannel(rgba, width, height, bx, by, which[k], channel);
					channelBlock(channel, out, o + k * 8);
					#end
				}
				o += stride;
			}
	}

	/** Block `(bx, by)`'s pixels' red, green and blue, three a pixel, its edge repeated past the image. **/
	static inline function gather(rgba:Bytes, width:Int, height:Int, bx:Int, by:Int, block:haxe.ds.Vector<Int>):Void
		for (i in 0...16) {
			var x = (bx << 2) + (i & 3), y = (by << 2) + (i >> 2);
			if (x >= width) x = width - 1;
			if (y >= height) y = height - 1;
			var p = (y * width + x) << 2;
			block[i * 3] = rgba.get(p);
			block[i * 3 + 1] = rgba.get(p + 1);
			block[i * 3 + 2] = rgba.get(p + 2);
		}

	static inline function gatherChannel(rgba:Bytes, width:Int, height:Int, bx:Int, by:Int, c:Int, channel:haxe.ds.Vector<Int>):Void
		for (i in 0...16) {
			var x = (bx << 2) + (i & 3), y = (by << 2) + (i >> 2);
			if (x >= width) x = width - 1;
			if (y >= height) y = height - 1;
			channel[i] = rgba.get(((y * width + x) << 2) + c);
		}

	/** A BC1 block of `block`'s 16 colours at `out[o]`. **/
	static function colorBlock(block:haxe.ds.Vector<Int>, out:Bytes, o:Int):Void {
		var r0 = 255, g0 = 255, b0 = 255, r1 = 0, g1 = 0, b1 = 0, sr = 0, sg = 0, sb = 0;
		for (i in 0...16) {
			var r = block[i * 3], g = block[i * 3 + 1], b = block[i * 3 + 2];
			if (r < r0) r0 = r;
			if (g < g0) g0 = g;
			if (b < b0) b0 = b;
			if (r > r1) r1 = r;
			if (g > g1) g1 = g;
			if (b > b1) b1 = b;
			sr += r;
			sg += g;
			sb += b;
		}
		// Which diagonal of the box the colours run along: green and blue against red, or with it.
		var cg = 0, cb = 0;
		for (i in 0...16) {
			var dr = block[i * 3] * 16 - sr;
			cg += dr * (block[i * 3 + 1] * 16 - sg);
			cb += dr * (block[i * 3 + 2] * 16 - sb);
		}
		if (cg < 0) {
			var t = g0;
			g0 = g1;
			g1 = t;
		}
		if (cb < 0) {
			var t = b0;
			b0 = b1;
			b1 = t;
		}
		// Inset by a sixteenth of the range, as the colours at the very ends are rarely all needed.
		var ir = (r1 - r0) >> 4, ig = (g1 - g0) >> 4, ib = (b1 - b0) >> 4;
		r0 += ir;
		r1 -= ir;
		g0 += ig;
		g1 -= ig;
		b0 += ib;
		b1 -= ib;
		var c0 = pack565(r1, g1, b1), c1 = pack565(r0, g0, b0);
		if (c0 < c1) {
			var t = c0;
			c0 = c1;
			c1 = t;
		}
		var idx = 0;
		if (c0 != c1) {
			// The endpoints as the GPU expands them, and each pixel's place between them, in sixths.
			var er0 = expand5(c0 >> 11), eg0 = expand6((c0 >> 5) & 63), eb0 = expand5(c0 & 31);
			var er1 = expand5(c1 >> 11), eg1 = expand6((c1 >> 5) & 63), eb1 = expand5(c1 & 31);
			var dr = er1 - er0, dg = eg1 - eg0, db = eb1 - eb0;
			var dd = dr * dr + dg * dg + db * db;
			for (i in 0...16) {
				var t = (block[i * 3] - er0) * dr + (block[i * 3 + 1] - eg0) * dg + (block[i * 3 + 2] - eb0) * db;
				var s = t * 6;
				// 0 is c0, 2 two thirds c0, 3 one third c0, 1 is c1.
				var q = s < dd ? 0 : s < 3 * dd ? 2 : s < 5 * dd ? 3 : 1;
				idx |= q << (i * 2);
			}
		}
		out.setUInt16(o, c0);
		out.setUInt16(o + 2, c1);
		out.setInt32(o + 4, idx);
	}

	/** A BC4 block of `v`'s 16 values at `out[o]`: their extremes as endpoints, each the nearest of the eight between. **/
	static function channelBlock(v:haxe.ds.Vector<Int>, out:Bytes, o:Int):Void {
		var lo = 255, hi = 0;
		for (i in 0...16) {
			if (v[i] < lo) lo = v[i];
			if (v[i] > hi) hi = v[i];
		}
		var range = hi - lo;
		var bits0 = 0, bits1 = 0;
		if (range > 0)
			for (i in 0...16) {
				// Its level, 0 at lo to 7 at hi, rounded to nearest.
				var level = Std.int(((v[i] - lo) * 14 + range) / (range * 2));
				var q = levelIndex(level);
				if (i < 8) bits0 |= q << (i * 3) else bits1 |= q << ((i - 8) * 3);
			}
		writeChannel(out, o, hi, lo, bits0, bits1);
	}

	#if (ash_simd && hl)
	/** `channelBlock`, its extremes and levels found sixteen at once; the same block. **/
	static function channelBlockSimd(rgba:Bytes, width:Int, height:Int, bx:Int, by:Int, c:Int, s:hl.Bytes, out:Bytes, o:Int):Void {
		var data:hl.Bytes = rgba;
		for (i in 0...16) {
			var x = (bx << 2) + (i & 3), y = (by << 2) + (i >> 2);
			if (x >= width) x = width - 1;
			if (y >= height) y = height - 1;
			s.setUI8(i, data.getUI8(((y * width + x) << 2) + c));
		}
		var lo = ash.simd.Vec.u8x16MinLane(s, 0), hi = ash.simd.Vec.u8x16MaxLane(s, 0);
		var range = hi - lo;
		var bits0 = 0, bits1 = 0;
		if (range > 0) {
			// Each value's level: how many of the seven midpoints between levels it is at or past.
			ash.simd.Vec.u8x16Splat(s, 48, 0);
			for (k in 1...8) {
				ash.simd.Vec.u8x16Splat(s, 16, lo + Std.int((range * (2 * k - 1) + 13) / 14));
				ash.simd.Vec.u8x16Ge(s, 32, s, 0, s, 16);
				ash.simd.Vec.u8x16Sub(s, 48, s, 48, s, 32);
			}
			for (i in 0...16) {
				var q = levelIndex(s.getUI8(48 + i));
				if (i < 8) bits0 |= q << (i * 3) else bits1 |= q << ((i - 8) * 3);
			}
		}
		writeChannel(out, o, hi, lo, bits0, bits1);
	}
	#end

	/** Where level `level` (0 at the low endpoint, 7 at the high) is in a BC4 block's order: high first, low second, then from high down. **/
	static inline function levelIndex(level:Int):Int
		return level == 7 ? 0 : level == 0 ? 1 : 8 - level;

	static inline function writeChannel(out:Bytes, o:Int, hi:Int, lo:Int, bits0:Int, bits1:Int):Void {
		out.set(o, hi);
		out.set(o + 1, lo);
		out.set(o + 2, bits0 & 0xff);
		out.set(o + 3, (bits0 >> 8) & 0xff);
		out.set(o + 4, (bits0 >> 16) & 0xff);
		out.set(o + 5, bits1 & 0xff);
		out.set(o + 6, (bits1 >> 8) & 0xff);
		out.set(o + 7, (bits1 >> 16) & 0xff);
	}

	static inline function pack565(r:Int, g:Int, b:Int):Int
		return Std.int((r * 31 + 127) / 255) << 11 | Std.int((g * 63 + 127) / 255) << 5 | Std.int((b * 31 + 127) / 255);

	static inline function expand5(v:Int):Int
		return (v << 3) | (v >> 2);

	static inline function expand6(v:Int):Int
		return (v << 2) | (v >> 4);
}
