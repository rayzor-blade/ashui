package ashui.draw3d;

import ashui.math.Vec3;
import haxe.io.Bytes;

/**
	Light from all around a 3D scene: a sky, as a cubemap. Surfaces reflect
	it, sharply where they are polished and blurred where they are rough,
	and are lit by its average from the way they face; a scene can show it
	behind its meshes too (`Scene3D.skybox`).

	Made from a Radiance `.hdr` photo of the whole sky (`fromHdr`), the
	kind HDRI sites give, or from colours (`gradient`). Its faces are
	`size` texels square, with every mip level each half the last, each
	the average of four below it, so a level is the sky blurred as a rough
	surface blurs it. Texels are 16-bit floats, eight bytes each: brighter
	than white where the sky is.

	Its pixels are freed once it is on the GPU, and its GPU copy by
	`dispose`.
**/
class Environment {
	/** Texels along a face's edge, at the sharpest level. **/
	public final size:Int;

	/** How many mip levels, the last one texel a face. **/
	public final levels:Int;

	/** Each level's six faces in WebGPU's order (+X, -X, +Y, -Y, +Z, -Z), row by row, RGBA as 16-bit floats; null once uploaded. **/
	@:noCompletion public var faces:Null<Array<Bytes>>;

	/** Called with each environment as it is disposed: what holds a copy of it lets it go. **/
	@:noCompletion public static final disposing:Array<Environment->Void> = [];

	/** Frees it; it must not be drawn with after. **/
	public function dispose():Void {
		for (f in disposing)
			f(this);
		faces = null;
	}

	function new(size:Int, faces:Array<Bytes>) {
		this.size = size;
		this.levels = faces.length;
		this.faces = faces;
	}

	/**
		From the bytes of a Radiance `.hdr` file, an equirectangular photo of
		the whole sky (2:1, the horizon across its middle), into faces `size`
		texels square. Throws when they are not one.
	**/
	public static function fromHdr(bytes:Bytes, size = 256):Environment {
		var sky = Rgbe.decode(bytes);
		return fill(size, sky.sampleInto);
	}

	/** A sky from `zenith` overhead to `horizon` round the level to `ground` below, `0xRRGGBB`, each times `intensity`. **/
	public static function gradient(zenith:Int, horizon:Int, ground:Int, intensity = 1.0, size = 64):Environment {
		inline function lin(c:Int, shift:Int):Float {
			var v = (c >> shift & 0xff) / 255;
			return (v <= 0.04045 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4)) * intensity;
		}
		var z = [lin(zenith, 16), lin(zenith, 8), lin(zenith, 0)];
		var h = [lin(horizon, 16), lin(horizon, 8), lin(horizon, 0)];
		var g = [lin(ground, 16), lin(ground, 8), lin(ground, 0)];
		return fill(size, (x, y, z2, out) -> {
			var to = y >= 0 ? z : g, t = y >= 0 ? Math.pow(y, 0.6) : Math.min(1, -y * 4);
			for (c in 0...3)
				out[c] = h[c] + (to[c] - h[c]) * t;
		});
	}

	/** Faces `size` square of the light `radiance` gives each way, linear, averaged over four points a texel. **/
	public static function fromFunction(size:Int, radiance:Vec3->Vec3):Environment
		return fill(size, (x, y, z, out) -> {
			var c = radiance(new Vec3(x, y, z));
			out[0] = c.x;
			out[1] = c.y;
			out[2] = c.z;
		});

	/**
		Faces `size` square, each texel the average of `sample` at four points
		in it: `sample(x, y, z, out)` writes the light from the unit direction
		`(x, y, z)` into `out[0..2]`. Nothing is made a sample, so a large sky
		leaves no garbage behind.
	**/
	static function fill(size:Int, sample:(Float, Float, Float, haxe.ds.Vector<Float>) -> Void):Environment {
		var one = new haxe.ds.Vector<Float>(3);
		var levels = 1;
		while ((size >> levels) > 0)
			levels++;
		var top = [for (_ in 0...6) new haxe.ds.Vector<Float>(size * size * 3)];
		for (face in 0...6) {
			var out = top[face];
			for (y in 0...size)
				for (x in 0...size) {
					var r = 0.0, g = 0.0, b = 0.0;
					for (k in 0...4) {
						var u = (x + (k & 1 == 0 ? 0.25 : 0.75)) / size * 2 - 1, v = (y + (k < 2 ? 0.25 : 0.75)) / size * 2 - 1;
						// The way through (u, v) on this face, as `direction` gives it, unnormalized.
						var dx = 0.0, dy = 0.0, dz = 0.0;
						switch face {
							case 0: dx = 1; dy = -v; dz = -u;
							case 1: dx = -1; dy = -v; dz = u;
							case 2: dx = u; dy = 1; dz = v;
							case 3: dx = u; dy = -1; dz = -v;
							case 4: dx = u; dy = -v; dz = 1;
							case _: dx = -u; dy = -v; dz = -1;
						}
						var l = 1 / Math.sqrt(dx * dx + dy * dy + dz * dz);
						sample(dx * l, dy * l, dz * l, one);
						r += one[0];
						g += one[1];
						b += one[2];
					}
					var i = (y * size + x) * 3;
					out[i] = r / 4;
					out[i + 1] = g / 4;
					out[i + 2] = b / 4;
				}
		}
		var faces = [];
		var current = top, n = size;
		for (level in 0...levels) {
			var bytes = Bytes.alloc(n * n * 8 * 6);
			for (face in 0...6) {
				var src = current[face];
				for (i in 0...n * n) {
					var o = (face * n * n + i) * 8;
					bytes.setUInt16(o, half(src[i * 3]));
					bytes.setUInt16(o + 2, half(src[i * 3 + 1]));
					bytes.setUInt16(o + 4, half(src[i * 3 + 2]));
					bytes.setUInt16(o + 6, 0x3C00);
				}
			}
			faces.push(bytes);
			if (n > 1) {
				var m = n >> 1;
				current = [
					for (face in 0...6) {
						var src = current[face], dst = new haxe.ds.Vector<Float>(m * m * 3);
						for (y in 0...m)
							for (x in 0...m)
								for (c in 0...3)
									dst[(y * m + x) * 3 + c] = (src[((y * 2) * n + x * 2) * 3 + c] + src[((y * 2) * n + x * 2 + 1) * 3 + c]
										+ src[((y * 2 + 1) * n + x * 2) * 3 + c] + src[((y * 2 + 1) * n + x * 2 + 1) * 3 + c]) / 4;
						dst;
					}
				];
				n = m;
			}
		}
		return new Environment(size, faces);
	}

	/** The way through texel `(u, v)`, -1 to 1 across and down, of cube face `face`, as WebGPU lays a cube out. **/
	public static function direction(face:Int, u:Float, v:Float):Vec3 {
		var d = switch face {
			case 0: new Vec3(1, -v, -u);
			case 1: new Vec3(-1, -v, u);
			case 2: new Vec3(u, 1, v);
			case 3: new Vec3(u, -1, -v);
			case 4: new Vec3(u, -v, 1);
			case _: new Vec3(-u, -v, -1);
		}
		return d.normalize();
	}

	/** `f` as a 16-bit float's bits, rounded to nearest, clamped to the largest finite one. **/
	@:noCompletion public static function half(f:Float):Int {
		if (!(f > 0))
			return 0;
		if (f >= 65504)
			return 0x7BFF;
		if (f < 6.103515625e-05)
			return Std.int(Math.round(f / 5.960464477539063e-08));
		var e = Math.floor(Math.log(f) / Math.log(2));
		var m = f / Math.pow(2, e) - 1;
		var mant = Std.int(Math.round(m * 1024));
		if (mant == 1024) {
			mant = 0;
			e++;
		}
		return ((e + 15) << 10) | mant;
	}
}

/** A Radiance `.hdr` image as it is stored, four bytes a pixel: red, green, blue and a shared exponent. **/
@:noCompletion class Rgbe {
	final width:Int;
	final height:Int;
	final pixels:Bytes;

	/** 2 to the power of each exponent byte, less 136: what a channel byte is multiplied by. **/
	static final SCALE = [for (e in 0...256) e == 0 ? 0.0 : Math.pow(2, e - 136)];

	function new(width:Int, height:Int, pixels:Bytes) {
		this.width = width;
		this.height = height;
		this.pixels = pixels;
	}

	public static function decode(b:Bytes):Rgbe {
		var at = 0;
		function line():String {
			var start = at;
			while (at < b.length && b.get(at) != 10)
				at++;
			var s = b.getString(start, at - start);
			at++;
			return s;
		}
		var magic = line();
		if (!StringTools.startsWith(magic, "#?"))
			throw "not a Radiance .hdr file";
		while (at < b.length && line() != "") {}
		var dims = line().split(" ");
		// "-Y height +X width": rows top to bottom, each left to right, the only layout HDRI files use.
		if (dims.length != 4 || dims[0] != "-Y" || dims[2] != "+X")
			throw 'unsupported .hdr layout: ${dims.join(" ")}';
		var height = Std.parseInt(dims[1]), width = Std.parseInt(dims[3]);
		var pixels = Bytes.alloc(width * height * 4);
		var row = Bytes.alloc(width * 4);
		for (y in 0...height) {
			if (width >= 8 && width < 32768 && b.get(at) == 2 && b.get(at + 1) == 2 && (b.get(at + 2) << 8 | b.get(at + 3)) == width) {
				// Run-length encoded: each of the four channels in turn, runs and literals.
				at += 4;
				for (c in 0...4) {
					var x = 0;
					while (x < width) {
						var count = b.get(at++);
						if (count > 128) {
							count -= 128;
							var v = b.get(at++);
							for (_ in 0...count)
								row.set((x++) * 4 + c, v);
						} else
							for (_ in 0...count)
								row.set((x++) * 4 + c, b.get(at++));
					}
				}
				pixels.blit(y * width * 4, row, 0, width * 4);
			} else {
				pixels.blit(y * width * 4, b, at, width * 4);
				at += width * 4;
			}
		}
		return new Rgbe(width, height, pixels);
	}

	/** The light the sky sends from direction `d`, interpolated between its four nearest pixels. **/
	public function sample(d:Vec3):Vec3 {
		var out = new haxe.ds.Vector<Float>(3);
		sampleInto(d.x, d.y, d.z, out);
		return new Vec3(out[0], out[1], out[2]);
	}

	/** `sample`, for the unit direction `(dx, dy, dz)`, written into `out[0..2]`. **/
	public function sampleInto(dx:Float, dy:Float, dz:Float, out:haxe.ds.Vector<Float>):Void {
		var u = 0.5 + Math.atan2(dx, -dz) / (2 * Math.PI);
		var v = Math.acos(Math.max(-1, Math.min(1, dy))) / Math.PI;
		var fx = u * width - 0.5, fy = Math.max(0, Math.min(height - 1, v * height - 0.5));
		var x0 = Math.floor(fx), y0 = Math.floor(fy);
		var tx = fx - x0, ty = fy - y0;
		var r = 0.0, g = 0.0, bl = 0.0;
		for (j in 0...2)
			for (i in 0...2) {
				var w = (i == 0 ? 1 - tx : tx) * (j == 0 ? 1 - ty : ty);
				var x = ((x0 + i) % width + width) % width, y = Std.int(Math.min(height - 1, y0 + j));
				var o = (y * width + x) * 4;
				var s = SCALE[pixels.get(o + 3)] * w;
				r += (pixels.get(o) + 0.5) * s;
				g += (pixels.get(o + 1) + 0.5) * s;
				bl += (pixels.get(o + 2) + 0.5) * s;
			}
		out[0] = r;
		out[1] = g;
		out[2] = bl;
	}
}
