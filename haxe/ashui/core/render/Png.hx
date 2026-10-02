package ashui.core.render;

import haxe.io.Bytes;
import haxe.io.BytesBuffer;

/** PNG encoding of 8-bit RGBA pixels, deflated with `haxe.zip.Compress`. **/
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

	/** `v` with its bytes reversed, so a little-endian write stores it big-endian. **/
	static inline function bigEndian(v:Int):Int {
		return ((v >>> 24) & 0xFF) | ((v >>> 8) & 0xFF00) | ((v << 8) & 0xFF0000) | (v << 24);
	}
}
