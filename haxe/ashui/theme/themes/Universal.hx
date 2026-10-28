package ashui.theme.themes;

import ashui.theme.Easing;
import ashui.theme.FontFamily;
import ashui.theme.TypographyTokens;

/** Shared typography and easing curves for the Universal themes. **/
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
		Uses Noto font families with platform fallbacks for consistent typography.
		The size scale starts at 12, 13, `textBase`, 17 and 20 pixels.
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
