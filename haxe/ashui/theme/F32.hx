package ashui.theme;

import haxe.io.FPHelper;

/**
	Single-precision arithmetic for values the theme shares with Blinc, which
	keeps them as f32: rounding a Float to the nearest f32, and printing one
	as Rust prints an f32, with the fewest digits that read back the same.
**/
class F32 {
	public static inline function round(x:Float):Float {
		return FPHelper.i32ToFloat(FPHelper.floatToI32(x));
	}

	/** `x` as Rust's `Display` for f32 prints it: `1`, `0.35`, `-0.025`, `2.5`. **/
	public static function toString(x:Float):String {
		var target = round(x);
		if (target == Math.ffloor(target) && Math.abs(target) < 1e15)
			return Std.string(Std.int(target));
		for (digits in 1...10) {
			var scale = Math.pow(10, digits);
			var candidate = Math.fround(target * scale) / scale;
			if (round(candidate) == target)
				return formatFixed(candidate, digits);
		}
		return Std.string(target);
	}

	static function formatFixed(x:Float, digits:Int):String {
		var negative = x < 0;
		var scaled = Std.string(Math.fround(Math.abs(x) * Math.pow(10, digits)));
		while (scaled.length <= digits)
			scaled = "0" + scaled;
		var whole = scaled.substr(0, scaled.length - digits);
		var frac = scaled.substr(scaled.length - digits);
		while (frac.length > 0 && frac.charAt(frac.length - 1) == "0")
			frac = frac.substr(0, frac.length - 1);
		return (negative ? "-" : "") + whole + (frac.length > 0 ? "." + frac : "");
	}
}
