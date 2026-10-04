import ashui.css.CssValue;

/** CSS values read into plain data: colours, lengths, calc(), angles, times, easings, gradients, shadows, transforms, filters. **/
class CssValues {
	static var failures = 0;

	static function check(name:String, ok:Bool, ?detail:Dynamic):Void {
		Sys.println((ok ? "ok   " : "FAIL ") + name + (ok || detail == null ? "" : ': $detail'));
		if (!ok)
			failures++;
	}

	static function fails(f:Void->Dynamic):Bool
		return try {
			f();
			false;
		} catch (_:String) true;

	static function rgba(text:String):String
		return switch CssValue.color(text) {
			case Rgba(rgb, a): '${StringTools.hex(rgb, 6)}/${Math.round(a * 100) / 100}';
			case CurrentColor: "current";
		}

	static final ctx:LengthContext = {
		percentOf: 200,
		fontSize: 20,
		rootFontSize: 16,
		viewportWidth: 1000,
		viewportHeight: 500,
		env: name -> name == "pointer-x" ? 0.5 : null
	};

	static function px(text:String):Float
		return CssValue.resolve(CssValue.length(text), ctx);

	static function main() {
		// --- Colours ---
		check("hex, 3, 4, 6 and 8 digits", rgba("#f80") == "FF8800/1" && rgba("#f808") == "FF8800/0.53" && rgba("#3B82F6") == "3B82F6/1"
			&& rgba("#3b82f680") == "3B82F6/0.5", [rgba("#f80"), rgba("#f808"), rgba("#3B82F6"), rgba("#3b82f680")]);
		check("rgb() with commas, spaces, percentages and alpha", rgba("rgb(255, 0, 0)") == "FF0000/1" && rgba("rgba(0,0,255,0.25)") == "0000FF/0.25"
			&& rgba("rgb(100% 50% 0% / 50%)") == "FF8000/0.5", [rgba("rgb(255, 0, 0)"), rgba("rgba(0,0,255,0.25)"), rgba("rgb(100% 50% 0% / 50%)")]);
		check("hsl()", rgba("hsl(0, 100%, 50%)") == "FF0000/1" && rgba("hsl(120 100% 50%)") == "00FF00/1" && rgba("hsla(240deg, 100%, 50%, 0.5)") == "0000FF/0.5",
			[rgba("hsl(0, 100%, 50%)"), rgba("hsl(120 100% 50%)"), rgba("hsla(240deg, 100%, 50%, 0.5)")]);
		var mixes = [
			rgba("color-mix(in srgb, #ff0000, #0000ff)"), rgba("color-mix(in srgb, white 90%, black)"),
			rgba("color-mix(in srgb, #ff0000 10%, transparent)"), rgba("color-mix(in srgb, red 20%, blue 20%)")
		];
		check("color-mix() in srgb: even by default, the rest of 100, premultiplied over transparent, an alpha under 100",
			mixes.join(" ") == "800080/1 E6E6E6/1 FF0000/0.1 800080/0.4", mixes);
		check("named colours, transparent and currentcolor", rgba("RebeccaPurple") == "663399/1" && rgba("transparent") == "000000/0"
			&& rgba("currentColor") == "current");
		check("a bad colour is refused", fails(() -> CssValue.color("#12")) && fails(() -> CssValue.color("blurple")) && fails(() -> CssValue.color("lab(50 0 0)")));

		// --- Lengths and calc() ---
		check("units resolve against their context", px("12px") == 12 && px("50%") == 100 && px("2em") == 40 && px("2rem") == 32 && px("10vw") == 100
			&& px("10vh") == 50 && px("10vmin") == 50 && px("0") == 0, [px("12px"), px("50%"), px("2em"), px("2rem"), px("10vw"), px("10vh"), px("10vmin")]);
		check("a bare number other than 0 is not a length", fails(() -> CssValue.length("12")));
		check("auto only where allowed", Math.isNaN(CssValue.resolve(CssValue.length("auto", true), ctx)) && fails(() -> CssValue.length("auto")));
		check("calc() with precedence and parentheses", px("calc(100% - 40px)") == 160 && px("calc(10px + 2 * 5px)") == 20
			&& px("calc((10px + 2px) * 2)") == 24 && px("calc(1rem + -4px)") == 12, [px("calc(100% - 40px)"), px("calc(10px + 2 * 5px)"), px("calc((10px + 2px) * 2)")]);
		check("min(), max(), clamp()", px("min(50%, 120px)") == 100 && px("max(10px, 2em)") == 40 && px("clamp(10px, 50%, 60px)") == 60);
		check("calc() needs spaces around + and -", fails(() -> CssValue.length("calc(10px+2px)")));
		var tilt = CssValue.calc("calc(env(pointer-x) * 20deg)");
		check("env() reads the environment, and makes it dynamic", CssValue.isDynamic(tilt) && !CssValue.isDynamic(CssValue.calc("calc(1px + 2px)")));
		check("fixed lengths are told apart", CssValue.isFixed(CssValue.length("calc(1px + 2px)")) && !CssValue.isFixed(CssValue.length("calc(1px + 2%)")));

		// --- Angles, times, easings ---
		check("angles in radians", Math.abs(CssValue.angle("180deg") - Math.PI) < 1e-9 && Math.abs(CssValue.angle("0.25turn") - Math.PI / 2) < 1e-9
			&& CssValue.angle("0") == 0 && fails(() -> CssValue.angle("90")));
		check("times in seconds", CssValue.time("150ms") == 0.15 && CssValue.time("2s") == 2 && fails(() -> CssValue.time("150")));
		check("easings", CssValue.easing("ease-out").equals(CubicBezier(0, 0, 0.58, 1)) && CssValue.easing("cubic-bezier(0.2, 0, 0, 1)").equals(CubicBezier(0.2, 0, 0, 1))
			&& CssValue.easing("steps(4, jump-start)").equals(Steps(4, true)) && fails(() -> CssValue.easing("cubic-bezier(2, 0, 0, 1)")));

		// --- Gradients ---
		switch CssValue.gradient("linear-gradient(to right, #fff, rgb(0, 0, 0) 80%)") {
			case Linear(a, stops):
				check("linear-gradient to a side, with stops", Math.abs(a - Math.PI / 2) < 1e-9 && stops.length == 2 && stops[0].offset == null
					&& stops[1].offset == 0.8, [a, stops]);
			case g:
				check("linear-gradient to a side, with stops", false, g);
		}
		switch CssValue.gradient("linear-gradient(45deg, red 0 50%, blue 50% 100%)") {
			case Linear(a, stops):
				check("an angle, and a stop at two offsets", Math.abs(a - Math.PI / 4) < 1e-9 && stops.length == 4, stops);
			case g:
				check("an angle, and a stop at two offsets", false, g);
		}
		switch CssValue.gradient("radial-gradient(circle at 25% top, white, black)") {
			case Radial(circle, x, y, stops):
				check("radial-gradient's shape and centre", circle && x == 0.25 && y == 0 && stops.length == 2, [circle, x, y]);
			case g:
				check("radial-gradient's shape and centre", false, g);
		}
		check("conic gradients are refused", fails(() -> CssValue.gradient("conic-gradient(red, blue)")));

		// --- Shadows ---
		var s = CssValue.shadows("0 1px 2px rgba(0,0,0,0.1), inset 0 0 0 1px #fff");
		check("box-shadow layers, inset, defaults", s.length == 2 && !s[0].inset && s[1].inset && s[0].spread.equals(Px(0)) && s[1].spread.equals(Px(1)),
			s);
		check("a shadow's colour may come first, and defaults to currentcolor", CssValue.shadows("red 2px 2px")[0].color.equals(Rgba(0xff0000, 1))
			&& CssValue.shadows("2px 2px")[0].color.equals(CurrentColor));
		check("none is no shadows", CssValue.shadows("none").length == 0);

		// --- Transforms ---
		var t = CssValue.transforms("translate(10px, 50%) rotate(90deg) scale(1.5) skewX(10deg)");
		check("transform functions, in order", t.length == 4 && t[0].equals(Translate(Px(10), Percent(50))) && t[2].equals(Scale(1.5, 1.5)), t);
		check("a 3D transform is refused", fails(() -> CssValue.transforms("rotateX(10deg)")));

		// --- Filters ---
		var f = CssValue.filters("brightness(120%) blur(4px) hue-rotate(0.5turn) drop-shadow(0 2px 4px black)");
		check("filter functions", f.length == 4 && f[0].equals(Brightness(1.2)) && f[1].equals(Blur(Px(4))), f);

		Sys.println(failures == 0 ? "ALL PASSED" : '$failures FAILED');
		Sys.exit(failures == 0 ? 0 : 1);
	}
}
