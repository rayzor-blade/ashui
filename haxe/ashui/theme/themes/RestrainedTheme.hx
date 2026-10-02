package ashui.theme.themes;

import ashui.theme.*;

/** Universal HID · Restrained: Apple-leaning, quiet surfaces and the strongest squircle. **/
class RestrainedTheme {
	public static inline var NAME = "Universal · Restrained";

	public static function bundle():ThemeBundle {
		return new ThemeBundle(NAME, light(), dark());
	}

	public static function light():Theme {
		return scheme(Light, lightColors(), lightShadows());
	}

	public static function dark():Theme {
		return scheme(Dark, darkColors(), darkShadows());
	}

	static function scheme(colorScheme:ColorScheme, colors:ColorTokens, shadows:ShadowTokens):Theme {
		return new Theme(NAME, colorScheme, colors, Universal.typography(15), SpacingTokens.defaults(), radii(), shadows, animations(), shape());
	}

	/** `radiusDefault` sits at the squircle threshold, so unmarked surfaces are smoothed. **/
	public static function radii():RadiusTokens {
		return {
			radiusNone: 0,
			radiusSm: 3,
			radiusDefault: 12,
			radiusMd: 8,
			radiusLg: 10,
			radiusXl: 14,
			radius2xl: 18,
			radius3xl: 24,
			radiusFull: 9999
		};
	}

	public static function shape():ShapeTokens {
		return new ShapeTokens(0.65, 4.4, 12);
	}

	public static function animations():AnimationTokens {
		return {
			durationFastest: 75,
			durationFaster: 100,
			durationFast: 150,
			durationNormal: 200,
			durationSlow: 280,
			durationSlower: 360,
			durationSlowest: 460,
			easeDefault: Universal.STANDARD,
			easeIn: EaseIn,
			easeOut: Universal.STANDARD,
			easeInOut: EaseInOut,
			easeState: Universal.STANDARD,
			easeNav: Universal.HIG_SHEET,
			easeSpring: Universal.SUBTLE_SPRING,
			easeSheet: Universal.HIG_SHEET
		};
	}

	static function lightColors():ColorTokens {
		return {
			primary: Rgba.fromHex(0x0A6CF0),
			primaryHover: Rgba.fromHex(0x0858CC),
			primaryActive: Rgba.fromHex(0x0A47A8),
			secondary: Rgba.fromHex(0x5E5E66),
			secondaryHover: Rgba.fromHex(0x46464C),
			secondaryActive: Rgba.fromHex(0x36363B),
			success: Rgba.fromHex(0x1F9D55),
			successBg: Rgba.fromHex(0x1F9D55).withAlpha(0.10),
			warning: Rgba.fromHex(0xC28200),
			warningBg: Rgba.fromHex(0xC28200).withAlpha(0.10),
			error: Rgba.fromHex(0xD8392C),
			errorBg: Rgba.fromHex(0xD8392C).withAlpha(0.10),
			info: Rgba.fromHex(0x1991DB),
			infoBg: Rgba.fromHex(0x1991DB).withAlpha(0.10),
			background: Rgba.fromHex(0xF5F6F8),
			surface: Rgba.WHITE,
			surfaceElevated: Rgba.WHITE,
			surfaceOverlay: Rgba.fromHex(0xECEEF2),
			textPrimary: Rgba.fromHex(0x14181F),
			textSecondary: Rgba.fromHex(0x5B6271),
			textTertiary: Rgba.fromHex(0x9098A6),
			textInverse: Rgba.WHITE,
			textLink: Rgba.fromHex(0x0A6CF0),
			border: Rgba.fromHex(0x14181F).withAlpha(0.10),
			borderSecondary: Rgba.fromHex(0xD5D9E0),
			borderHover: Rgba.fromHex(0x14181F).withAlpha(0.16),
			borderFocus: Rgba.fromHex(0x0A6CF0),
			borderError: Rgba.fromHex(0xD8392C),
			inputBg: Rgba.WHITE,
			inputBgHover: Rgba.fromHex(0xFAFBFC),
			inputBgFocus: Rgba.WHITE,
			inputBgDisabled: Rgba.fromHex(0xF0F1F4),
			selection: Rgba.fromHex(0x0A6CF0).withAlpha(0.22),
			selectionText: Rgba.fromHex(0x14181F),
			accent: Rgba.fromHex(0x0A6CF0),
			accentSubtle: Rgba.fromHex(0x0A6CF0).withAlpha(0.10),
			tooltipBg: Rgba.fromHex(0x1C1F26),
			tooltipText: Rgba.fromHex(0xF5F6F8)
		};
	}

	static function darkColors():ColorTokens {
		return {
			primary: Rgba.fromHex(0x4F94FF),
			primaryHover: Rgba.fromHex(0x6FA8FF),
			primaryActive: Rgba.fromHex(0x8FBCFF),
			secondary: Rgba.fromHex(0xA6A6AD),
			secondaryHover: Rgba.fromHex(0xBFBFC4),
			secondaryActive: Rgba.fromHex(0xD8D8DB),
			success: Rgba.fromHex(0x3DCB7B),
			successBg: Rgba.fromHex(0x3DCB7B).withAlpha(0.14),
			warning: Rgba.fromHex(0xE8A93B),
			warningBg: Rgba.fromHex(0xE8A93B).withAlpha(0.14),
			error: Rgba.fromHex(0xFF6258),
			errorBg: Rgba.fromHex(0xFF6258).withAlpha(0.14),
			info: Rgba.fromHex(0x5BB6E8),
			infoBg: Rgba.fromHex(0x5BB6E8).withAlpha(0.14),
			background: Rgba.fromHex(0x0F1216),
			surface: Rgba.fromHex(0x181C22),
			surfaceElevated: Rgba.fromHex(0x232830),
			surfaceOverlay: Rgba.fromHex(0x0B0D11),
			textPrimary: Rgba.fromHex(0xF2F4F7),
			textSecondary: Rgba.fromHex(0xA9B0BD),
			textTertiary: Rgba.fromHex(0x717886),
			textInverse: Rgba.fromHex(0x0F1216),
			textLink: Rgba.fromHex(0x4F94FF),
			border: Rgba.WHITE.withAlpha(0.10),
			borderSecondary: Rgba.fromHex(0x353A45),
			borderHover: Rgba.WHITE.withAlpha(0.16),
			borderFocus: Rgba.fromHex(0x4F94FF),
			borderError: Rgba.fromHex(0xFF6258),
			inputBg: Rgba.fromHex(0x181C22),
			inputBgHover: Rgba.fromHex(0x1F242C),
			inputBgFocus: Rgba.fromHex(0x181C22),
			inputBgDisabled: Rgba.fromHex(0x13161B),
			selection: Rgba.fromHex(0x4F94FF).withAlpha(0.34),
			selectionText: Rgba.fromHex(0xF2F4F7),
			accent: Rgba.fromHex(0x4F94FF),
			accentSubtle: Rgba.fromHex(0x4F94FF).withAlpha(0.14),
			tooltipBg: Rgba.fromHex(0xF2F4F7),
			tooltipText: Rgba.fromHex(0x14181F)
		};
	}

	static function lightShadows():ShadowTokens {
		return {
			shadowSm: [new Shadow(0, 0, 1, 0, Rgba.fromHex(0x0F141E).withAlpha(0.04)), new Shadow(0, 1, 1.5, 0, Rgba.fromHex(0x0F141E).withAlpha(0.06))],
			shadowDefault: [new Shadow(0, 0, 1, 0, Rgba.fromHex(0x0F141E).withAlpha(0.05)), new Shadow(0, 1, 2, 0, Rgba.fromHex(0x0F141E).withAlpha(0.07))],
			shadowMd: [new Shadow(0, 1, 2, 0, Rgba.fromHex(0x0F141E).withAlpha(0.04)), new Shadow(0, 4, 8, 0, Rgba.fromHex(0x0F141E).withAlpha(0.05))],
			shadowLg: [new Shadow(0, 2, 4, 0, Rgba.fromHex(0x0F141E).withAlpha(0.05)), new Shadow(0, 12, 20, 0, Rgba.fromHex(0x0F141E).withAlpha(0.07))],
			shadowXl: [new Shadow(0, 4, 8, 0, Rgba.fromHex(0x0F141E).withAlpha(0.06)), new Shadow(0, 22, 36, 0, Rgba.fromHex(0x0F141E).withAlpha(0.09))],
			shadow2xl: [new Shadow(0, 6, 12, 0, Rgba.fromHex(0x0F141E).withAlpha(0.08)), new Shadow(0, 32, 64, 0, Rgba.fromHex(0x0F141E).withAlpha(0.14))],
			shadowInner: [new Shadow(0, 1, 2, 0, Rgba.fromHex(0x0F141E).withAlpha(0.06))],
			shadowNone: []
		};
	}

	static function darkShadows():ShadowTokens {
		return {
			shadowSm: [new Shadow(0, 0, 1, 0, Rgba.BLACK.withAlpha(0.20)), new Shadow(0, 1, 1.5, 0, Rgba.BLACK.withAlpha(0.30))],
			shadowDefault: [new Shadow(0, 0, 1, 0, Rgba.BLACK.withAlpha(0.25)), new Shadow(0, 1, 2, 0, Rgba.BLACK.withAlpha(0.40))],
			shadowMd: [new Shadow(0, 1, 2, 0, Rgba.BLACK.withAlpha(0.22)), new Shadow(0, 4, 8, 0, Rgba.BLACK.withAlpha(0.32))],
			shadowLg: [new Shadow(0, 2, 4, 0, Rgba.BLACK.withAlpha(0.26)), new Shadow(0, 12, 20, 0, Rgba.BLACK.withAlpha(0.38))],
			shadowXl: [new Shadow(0, 4, 8, 0, Rgba.BLACK.withAlpha(0.30)), new Shadow(0, 22, 36, 0, Rgba.BLACK.withAlpha(0.44))],
			shadow2xl: [new Shadow(0, 6, 12, 0, Rgba.BLACK.withAlpha(0.36)), new Shadow(0, 32, 64, 0, Rgba.BLACK.withAlpha(0.58))],
			shadowInner: [new Shadow(0, 1, 2, 0, Rgba.BLACK.withAlpha(0.30))],
			shadowNone: []
		};
	}
}
