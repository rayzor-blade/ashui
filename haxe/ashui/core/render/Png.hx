package ashui.core.render;

import haxe.io.Bytes;
import haxe.io.BytesBuffer;

/** PNG encoding and decoding of 8-bit RGBA pixels, deflated with `haxe.zip.Compress`. **/
class Png {
	/** `pixels` holds `width` × `height` RGBA pixels, rows top first, `stride` bytes apart. **/
	public static function encode(width:Int, height:Int, pixels:Bytes, ?stride:Int):Bytes {
		if (stride == null)
			stride = width * 4;
		// Each row starts with filter type 0, none.
		var raw = Bytes.alloc((width * 4 + 1) * height);
		for (y in 0...height) {
			raw.set(y * (width * 4 + 1), 0);
			raw.blit(y * (width * 4 + 1) + 1, pixels, y * stride, width * 4);
		}

		var header = Bytes.alloc(13);
		header.setInt32(0, bigEndian(width));
		header.setInt32(4, bigEndian(height));
		header.set(8, 8); // bits per channel
		header.set(9, 6); // RGBA
		header.set(10, 0);
		header.set(11, 0);
		header.set(12, 0);

		var out = new BytesBuffer();
		for (b in [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
			out.addByte(b);
		chunk(out, "IHDR", header);
		chunk(out, "IDAT", haxe.zip.Compress.run(raw, 6));
		chunk(out, "IEND", Bytes.alloc(0));
		return out.getBytes();
	}

	static function chunk(out:BytesBuffer, type:String, data:Bytes):Void {
		var typed = Bytes.alloc(4 + data.length);
		for (i in 0...4)
			typed.set(i, type.charCodeAt(i));
		typed.blit(4, data, 0, data.length);
		out.addInt32(bigEndian(data.length));
		out.addBytes(typed, 0, typed.length);
		out.addInt32(bigEndian(haxe.crypto.Crc32.make(typed)));
	}

	/**
		The pixels of an 8-bit RGBA PNG, rows top first: what `encode` writes,
		or any other non-interlaced one of that kind, whatever filters its
		rows use. Throws for any other kind.
	**/
	public static function decode(png:Bytes):{width:Int, height:Int, pixels:Bytes} {
		inline function u32(at:Int):Int
			return (png.get(at) << 24) | (png.get(at + 1) << 16) | (png.get(at + 2) << 8) | png.get(at + 3);
		if (png.length < 8 || png.get(0) != 0x89 || png.get(1) != 0x50)
			throw "not a PNG";
		var width = 0, height = 0;
		var data = new BytesBuffer();
		var at = 8;
		while (at + 8 <= png.length) {
			var length = u32(at);
			var type = png.getString(at + 4, 4);
			var body = at + 8;
			switch type {
				case "IHDR":
					width = u32(body);
					height = u32(body + 4);
					if (png.get(body + 8) != 8 || png.get(body + 9) != 6 || png.get(body + 12) != 0)
						throw "only 8-bit RGBA PNGs, not interlaced, are read";
				case "IDAT":
					data.addBytes(png, body, length);
				case "IEND":
					break;
				case _:
			}
			at = body + length + 4;
		}
		var raw = haxe.zip.Uncompress.run(data.getBytes());
		var row = width * 4;
		var pixels = Bytes.alloc(row * height);
		for (y in 0...height) {
			var filter = raw.get(y * (row + 1));
			var src = y * (row + 1) + 1, dst = y * row;
			for (x in 0...row) {
				var a = x >= 4 ? pixels.get(dst + x - 4) : 0;
				var b = y > 0 ? pixels.get(dst - row + x) : 0;
				var c = x >= 4 && y > 0 ? pixels.get(dst - row + x - 4) : 0;
				var v = raw.get(src + x);
				pixels.set(dst + x, (switch filter {
					case 0: v;
					case 1: v + a;
					case 2: v + b;
					case 3: v + ((a + b) >> 1);
					case 4: v + paeth(a, b, c);
					case _: throw 'unknown PNG filter $filter';
				}) & 0xFF);
			}
		}
		return {width: width, height: height, pixels: pixels};
	}

	static inline function paeth(a:Int, b:Int, c:Int):Int {
		var p = a + b - c;
		var pa = Std.int(Math.abs(p - a)), pb = Std.int(Math.abs(p - b)), pc = Std.int(Math.abs(p - c));
		return pa <= pb && pa <= pc ? a : pb <= pc ? b : c;
	}

	/** `v` with its bytes reversed, so a little-endian write stores it big-endian. **/
	static inline function bigEndian(v:Int):Int {
		return ((v >>> 24) & 0xFF) | ((v >>> 8) & 0xFF00) | ((v << 8) & 0xFF0000) | (v << 24);
	}
}
