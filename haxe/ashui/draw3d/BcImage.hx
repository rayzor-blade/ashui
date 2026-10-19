package ashui.draw3d;

import haxe.io.Bytes;

/**
	A texture already block-compressed (BC1, BC3, BC4 or BC5), every mip
	level of it, as a GPU samples it: what `BcEncoder` makes, and what a
	`.dds` file holds. A mesh texture made from one is uploaded as it is, so
	nothing is decoded, resampled or encoded when the program runs; the
	`bcpack` tool makes the files ahead of time.

	The file is DDS with a DX10 header, which names the format as DXGI does,
	and the levels follow it from the largest down, each of its 4×4 blocks
	8 or 16 bytes. Files with the older `DXT1`, `DXT5`, `ATI1` and `ATI2`
	codes are read too.
**/
class BcImage {
	/** DXGI's numbers for the formats; the sRGB ones are for colour, which a GPU then decodes as it samples. **/
	public static inline var BC1 = 71;

	public static inline var BC1_SRGB = 72;
	public static inline var BC3 = 77;
	public static inline var BC3_SRGB = 78;
	public static inline var BC4 = 80;
	public static inline var BC5 = 83;

	/** The size in pixels of the largest level. **/
	public final width:Int;

	public final height:Int;

	/** The format, as DXGI numbers it. **/
	public final format:Int;

	/** Each level's blocks, the largest first. **/
	public final levels:Array<Bytes>;

	public function new(width:Int, height:Int, format:Int, levels:Array<Bytes>) {
		if (blockBytes(format) == 0)
			throw 'not a block format: $format';
		this.width = width;
		this.height = height;
		this.format = format;
		this.levels = levels;
	}

	/** Bytes a block takes: 8 for BC1 and BC4, 16 for BC3 and BC5, 0 for another format. **/
	public static function blockBytes(format:Int):Int
		return switch format {
			case BC1 | BC1_SRGB | BC4: 8;
			case BC3 | BC3_SRGB | BC5: 16;
			case _: 0;
		};

	/** Bytes of the level `width` × `height` pixels, in blocks. **/
	public static function levelBytes(width:Int, height:Int, format:Int):Int
		return ((width + 3) >> 2) * ((height + 3) >> 2) * blockBytes(format);

	/** The size of level `level` of a texture `width` × `height`. **/
	public static inline function levelSize(side:Int, level:Int):Int
		return Std.int(Math.max(1, side >> level));

	/** The levels a texture `width` × `height` has down to one pixel. **/
	public static function levelCount(width:Int, height:Int):Int {
		var count = 1;
		while ((width >> count) > 0 || (height >> count) > 0)
			count++;
		return count;
	}

	/** Reads a DDS file; throws when it is not one of a block format this knows, or is cut short. **/
	public static function parse(bytes:Bytes):BcImage {
		if (bytes.length < 128 || bytes.getInt32(0) != 0x20534444)
			throw "not a DDS file";
		if (bytes.getInt32(4) != 124)
			throw "bad DDS header";
		var height = bytes.getInt32(12), width = bytes.getInt32(16);
		var mips = Std.int(Math.max(1, bytes.getInt32(28)));
		var code = bytes.getInt32(84);
		var offset = 128;
		var format = switch code {
			case 0x30315844:
				// 'DX10': the format is in the header after it.
				if (bytes.length < 148)
					throw "DDS file cut short";
				offset = 148;
				bytes.getInt32(128);
			case 0x31545844: BC1;
			case 0x35545844: BC3;
			case 0x31495441: BC4;
			case 0x32495441: BC5;
			case _: throw 'DDS format code $code is not block-compressed';
		};
		if (blockBytes(format) == 0)
			throw 'DDS format $format is not one of BC1, BC3, BC4 and BC5';
		if (width <= 0 || height <= 0)
			throw "bad DDS size";
		var levels = [];
		for (level in 0...mips) {
			var size = levelBytes(levelSize(width, level), levelSize(height, level), format);
			if (offset + size > bytes.length)
				throw "DDS file cut short";
			levels.push(bytes.sub(offset, size));
			offset += size;
		}
		return new BcImage(width, height, format, levels);
	}

	/** The `.dds` file for it: a DX10 header, then each level's blocks. **/
	public function toDds():Bytes {
		var size = 148;
		for (level in levels)
			size += level.length;
		var out = Bytes.alloc(size);
		out.setInt32(0, 0x20534444);
		out.setInt32(4, 124);
		// Caps, height, width, pixel format, mip count and linear size.
		out.setInt32(8, 0x1 | 0x2 | 0x4 | 0x1000 | 0x20000 | 0x80000);
		out.setInt32(12, height);
		out.setInt32(16, width);
		out.setInt32(20, levels[0].length);
		out.setInt32(28, levels.length);
		// The pixel format: a four-character code, DX10.
		out.setInt32(76, 32);
		out.setInt32(80, 0x4);
		out.setInt32(84, 0x30315844);
		// Texture, mip map and complex.
		out.setInt32(108, 0x1000 | 0x400000 | 0x8);
		// The DX10 header: the format, a 2D texture, one of it.
		out.setInt32(128, format);
		out.setInt32(132, 3);
		out.setInt32(140, 1);
		var at = 148;
		for (level in levels) {
			out.blit(at, level, 0, level.length);
			at += level.length;
		}
		return out;
	}
}
