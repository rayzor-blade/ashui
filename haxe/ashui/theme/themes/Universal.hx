package ashui.theme.themes;

import ashui.theme.Easing;
import ashui.theme.FontFamily;
import ashui.theme.TypographyTokens;

/**
	What the Universal HID themes share: their type, and the timing curves
	they pick from.
**/
class Universal {
	public static final STANDARD = CubicBezier(0.25, 0.10, 0.25, 1.0);
	public static final HYBRID_NAV = CubicBezier(0.30, 0.70, 0.10, 1.0);
	public static final HYBRID_SPRING = CubicBezier(0.34, 1.30, 0.64, 1.0);
	public static final HIG_SHEET = CubicBezier(0.32, 0.72, 0.0, 1.0);
	public static final SUBTLE_SPRING = CubicBezier(0.34, 1.20, 0.64, 1.0);
	public static final EMPHASIZED = CubicBezier(0.20, 0, 0, 1);
	public static final EMPH_DECEL = CubicBezier(0.05, 0.70, 0.10, 1);
	public static final EXPRESSIVE_SPRING = CubicBezier(0.34, 1.56, 0.64, 1.0);

	/**
		Noto everywhere, so a Universal theme looks the same whatever the
		platform's fonts, on the HID scale: 12 / 13 / base / 17 / 20 / …
	**/
	public static function typography(textBase:Float):TypographyTokens {
		return TypographyTokens.defaults().with({
			fontSans: new FontFamily("Noto Sans", ["system-ui", "-apple-system", "Segoe UI", "Roboto", "sans-serif"]),
			fontSerif: new FontFamily("Noto Serif", ["ui-serif", "Georgia", "serif"]),
			fontMono: new FontFamily("Noto Sans Mono", ["ui-monospace", "SF Mono", "Menlo", "monospace"]),
			textXs: 12.0,
			textSm: 13.0,
			textBase: textBase,
			textLg: 17.0,
			textXl: 20.0,
			text2xl: 24.0,
			text3xl: 30.0,
			text4xl: 36.0,
			text5xl: 48.0
		});
	}
}
