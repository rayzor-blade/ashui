package ashui.theme;

/**
	A colour of the theme: red, green, blue and alpha from 0 to 1, in sRGB.
	Each component is rounded to single precision (see `F32`), as the
	native library keeps colours, so values and their CSS forms match what
	it gives. Mirrors Blinc's `Color`.
**/
@:structInit
final class Rgba {
	public static final WHITE:Rgba = rgba(1, 1, 1, 1);
	public static final BLACK:Rgba = rgba(0, 0, 0, 1);
	public static final TRANSPARENT:Rgba = rgba(0, 0, 0, 0);

	public final r:Float;
	public final g:Float;
	public final b:Float;
	public final a:Float;

	public function new(r:Float, g:Float, b:Float, a:Float) {
		this.r = F32.round(r);
		this.g = F32.round(g);
		this.b = F32.round(b);
		this.a = F32.round(a);
	}

	public static inline function rgba(r:Float, g:Float, b:Float, a:Float):Rgba {
		return new Rgba(r, g, b, a);
	}

	/** `0xRRGGBB`, opaque. **/
	public static function fromHex(hex:Int):Rgba {
		return new Rgba(F32.round(((hex >> 16) & 0xFF) / 255), F32.round(((hex >> 8) & 0xFF) / 255), F32.round((hex & 0xFF) / 255), 1);
	}

	/** This colour with its alpha replaced by `alpha`. **/
	public function withAlpha(alpha:Float):Rgba {
		return new Rgba(r, g, b, alpha);
	}

	/** From `from` to `to` by `t`, clamped to 0..1, each channel linearly. **/
	public static function lerp(from:Rgba, to:Rgba, t:Float):Rgba {
		var t = Math.max(0, Math.min(1, t));
		return new Rgba(from.r + (to.r - from.r) * t, from.g + (to.g - from.g) * t, from.b + (to.b - from.b) * t, from.a + (to.a - from.a) * t);
	}

	/** `channel` as a byte, 0 to 255, truncated rather than rounded as the native library's CSS is. **/
	public inline function byte(channel:Float):Int {
		return Std.int(F32.round(channel * 255));
	}

	/** `0xRRGGBB`. **/
	public function rgb():Int {
		return (byte(r) << 16) | (byte(g) << 8) | byte(b);
	}

	public function equals(other:Rgba):Bool {
		return r == other.r && g == other.g && b == other.b && a == other.a;
	}

	/** This colour as a style value for a node. **/
	public function toColor():ashui.types.Color {
		return new ashui.types.Color(rgb(), a);
	}

	/** This colour as a solid fill for a node. **/
	public function toBrush():ashui.types.Brush {
		return ashui.types.Brush.solid(rgb(), a);
	}

	public function toString():String {
		return 'Rgba($r, $g, $b, $a)';
	}
}
