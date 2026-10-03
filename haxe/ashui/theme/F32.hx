package ashui.theme;

import haxe.io.FPHelper;

/**
	Single-precision arithmetic for theme values the native library keeps as
	32-bit floats: rounding a Float to the nearest f32, so values compare
	equal on both sides, and printing one with the fewest digits that read
	back the same, as the library prints them in CSS.
**/
class F32 {
	/** `x` rounded to the nearest 32-bit float. **/
	public static inline function round(x:Float):Float {
		return FPHelper.i32ToFloat(FPHelper.floatToI32(x));
	}

	/**
		`x` in the fewest digits that read back as the same f32, a whole
		number without a point: `1`, `0.35`, `-0.025`, `2.5`.
	**/
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
