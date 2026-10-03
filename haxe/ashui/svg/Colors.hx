package ashui.svg;

/** CSS colours as SVG writes them: `#rgb`, `#rrggbb`, with alpha `#rgba` and `#rrggbbaa`, `rgb()`, `rgba()` and names. **/
class Colors {
	static final NAMES:Map<String, Int> = [
		"black" => 0x000000, "silver" => 0xc0c0c0, "gray" => 0x808080, "grey" => 0x808080, "white" => 0xffffff, "maroon" => 0x800000,
		"red" => 0xff0000, "purple" => 0x800080, "fuchsia" => 0xff00ff, "magenta" => 0xff00ff, "green" => 0x008000, "lime" => 0x00ff00,
		"olive" => 0x808000, "yellow" => 0xffff00, "navy" => 0x000080, "blue" => 0x0000ff, "teal" => 0x008080, "aqua" => 0x00ffff,
		"cyan" => 0x00ffff, "orange" => 0xffa500, "gold" => 0xffd700, "pink" => 0xffc0cb, "brown" => 0xa52a2a, "indigo" => 0x4b0082,
		"violet" => 0xee82ee, "crimson" => 0xdc143c, "coral" => 0xff7f50, "tomato" => 0xff6347, "salmon" => 0xfa8072,
		"skyblue" => 0x87ceeb, "steelblue" => 0x4682b4, "royalblue" => 0x4169e1, "slategray" => 0x708090, "darkgray" => 0xa9a9a9,
		"lightgray" => 0xd3d3d3, "dimgray" => 0x696969, "whitesmoke" => 0xf5f5f5, "gainsboro" => 0xdcdcdc
	];

	/** `v` as `0xRRGGBB` and an alpha from 0 to 1; throws `SvgError` when it is not a colour. **/
	public static function parse(v:String):{rgb:Int, alpha:Float} {
		var s = StringTools.trim(v).toLowerCase();
		if (StringTools.startsWith(s, "#")) {
			var hex = s.substr(1);
			if (!~/^[0-9a-f]+$/.match(hex))
				throw new SvgError('"$v" is not a colour');
			switch hex.length {
				case 3 | 4:
					var digits = [for (i in 0...hex.length) Std.parseInt("0x" + hex.charAt(i)) * 17];
					return {rgb: digits[0] << 16 | digits[1] << 8 | digits[2], alpha: hex.length == 4 ? digits[3] / 255 : 1};
				case 6 | 8:
					return {
						rgb: Std.parseInt("0x" + hex.substr(0, 6)),
						alpha: hex.length == 8 ? Std.parseInt("0x" + hex.substr(6)) / 255 : 1
					};
				case _:
					throw new SvgError('"$v" is not a colour');
			}
		}
		var fn = ~/^rgba?\(([^)]*)\)$/;
		if (fn.match(s)) {
			var parts = ~/[\s,\/]+/g.split(StringTools.trim(fn.matched(1)));
			if (parts.length != 3 && parts.length != 4)
				throw new SvgError('"$v" is not a colour');
			function channel(p:String):Int {
				var percent = StringTools.endsWith(p, "%");
				var f = Std.parseFloat(percent ? p.substr(0, p.length - 1) : p);
				if (Math.isNaN(f))
					throw new SvgError('"$v" is not a colour');
				return Std.int(Math.max(0, Math.min(255, Math.round(percent ? f * 2.55 : f))));
			}
			var alpha = parts.length == 4 ? SvgParser.unit(parts[3], "alpha") : 1.0;
			return {rgb: channel(parts[0]) << 16 | channel(parts[1]) << 8 | channel(parts[2]), alpha: alpha};
		}
		var named = NAMES.get(s);
		if (named == null)
			throw new SvgError('"$v" is not a colour ashui knows; write it as #rrggbb');
		return {rgb: named, alpha: 1};
	}
}
