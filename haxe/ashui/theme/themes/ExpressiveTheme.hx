package ashui.theme.themes;

import ashui.theme.*;

/** Universal HID · Expressive: Material-leaning, bolder colour and shadows tinted with the accent. **/
class ExpressiveTheme {
	public static inline var NAME = "Universal · Expressive";

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
			radiusSm: 4,
			radiusDefault: 16,
			radiusMd: 12,
			radiusLg: 16,
			radiusXl: 24,
			radius2xl: 28,
			radius3xl: 36,
			radiusFull: 9999
		};
	}

	public static function shape():ShapeTokens {
		return new ShapeTokens(0.2, 2.6, 16);
	}

	public static function animations():AnimationTokens {
		return {
			durationFastest: 100,
			durationFaster: 150,
			durationFast: 200,
			durationNormal: 280,
			durationSlow: 400,
			durationSlower: 500,
			durationSlowest: 650,
			easeDefault: Universal.EMPH_DECEL,
			easeIn: EaseIn,
			easeOut: Universal.EMPH_DECEL,
			easeInOut: Universal.EMPHASIZED,
			easeState: Universal.EMPH_DECEL,
			easeNav: Universal.EMPHASIZED,
			easeSpring: Universal.EXPRESSIVE_SPRING,
			easeSheet: Universal.EMPHASIZED
		};
	}

	static function lightColors():ColorTokens {
		return {
			primary: Rgba.fromHex(0x3D5FE8),
			primaryHover: Rgba.fromHex(0x314DD0),
			primaryActive: Rgba.fromHex(0x253BB0),
			secondary: Rgba.fromHex(0x665E7E),
			secondaryHover: Rgba.fromHex(0x504864),
			secondaryActive: Rgba.fromHex(0x3A344A),
			success: Rgba.fromHex(0x1E8B49),
			successBg: Rgba.fromHex(0xD9F2E0),
			warning: Rgba.fromHex(0xA06A12),
			warningBg: Rgba.fromHex(0xF8E6C0),
			error: Rgba.fromHex(0xB53A30),
			errorBg: Rgba.fromHex(0xFADAD5),
			info: Rgba.fromHex(0x0E7AB5),
			infoBg: Rgba.fromHex(0xD5ECF6),
			background: Rgba.fromHex(0xFBFAFE),
			surface: Rgba.WHITE,
			surfaceElevated: Rgba.fromHex(0xF4F4FE),
			surfaceOverlay: Rgba.fromHex(0xE5EBFE),
			textPrimary: Rgba.fromHex(0x161726),
			textSecondary: Rgba.fromHex(0x4B4F66),
			textTertiary: Rgba.fromHex(0x84899E),
			textInverse: Rgba.WHITE,
			textLink: Rgba.fromHex(0x3D5FE8),
			border: Rgba.fromHex(0x161726).withAlpha(0.10),
			borderSecondary: Rgba.fromHex(0xD2D5E5),
			borderHover: Rgba.fromHex(0x161726).withAlpha(0.18),
			borderFocus: Rgba.fromHex(0x3D5FE8),
			borderError: Rgba.fromHex(0xB53A30),
			inputBg: Rgba.WHITE,
			inputBgHover: Rgba.fromHex(0xF8F8FE),
			inputBgFocus: Rgba.WHITE,
			inputBgDisabled: Rgba.fromHex(0xECEDF8),
			selection: Rgba.fromHex(0x3D5FE8).withAlpha(0.24),
			selectionText: Rgba.fromHex(0x161726),
			accent: Rgba.fromHex(0x3D5FE8),
			accentSubtle: Rgba.fromHex(0xDCE3FF),
			tooltipBg: Rgba.fromHex(0x1A1B2B),
			tooltipText: Rgba.fromHex(0xFBFAFE)
		};
	}

	static function darkColors():ColorTokens {
		return {
			primary: Rgba.fromHex(0xB1C5FF),
			primaryHover: Rgba.fromHex(0xC4D2FF),
			primaryActive: Rgba.fromHex(0xD7E0FF),
			secondary: Rgba.fromHex(0xCFC8E2),
			secondaryHover: Rgba.fromHex(0xE2DCEF),
			secondaryActive: Rgba.fromHex(0xF0ECF8),
			success: Rgba.fromHex(0x5EDB89),
			successBg: Rgba.fromHex(0x5EDB89).withAlpha(0.18),
			warning: Rgba.fromHex(0xF2BD60),
			warningBg: Rgba.fromHex(0xF2BD60).withAlpha(0.18),
			error: Rgba.fromHex(0xFF7F73),
			errorBg: Rgba.fromHex(0xFF7F73).withAlpha(0.18),
			info: Rgba.fromHex(0x82C9F0),
			infoBg: Rgba.fromHex(0x82C9F0).withAlpha(0.18),
			background: Rgba.fromHex(0x11121A),
			surface: Rgba.fromHex(0x1B1D29),
			surfaceElevated: Rgba.fromHex(0x262838),
			surfaceOverlay: Rgba.fromHex(0x0A0B12),
			textPrimary: Rgba.fromHex(0xE4E5F0),
			textSecondary: Rgba.fromHex(0xB6BACA),
			textTertiary: Rgba.fromHex(0x7B8094),
			textInverse: Rgba.fromHex(0x11121A),
			textLink: Rgba.fromHex(0xB1C5FF),
			border: Rgba.WHITE.withAlpha(0.10),
			borderSecondary: Rgba.fromHex(0x3D4055),
			borderHover: Rgba.WHITE.withAlpha(0.20),
			borderFocus: Rgba.fromHex(0xB1C5FF),
			borderError: Rgba.fromHex(0xFF7F73),
			inputBg: Rgba.fromHex(0x1B1D29),
			inputBgHover: Rgba.fromHex(0x242636),
			inputBgFocus: Rgba.fromHex(0x1B1D29),
			inputBgDisabled: Rgba.fromHex(0x14151E),
			selection: Rgba.fromHex(0xB1C5FF).withAlpha(0.32),
			selectionText: Rgba.fromHex(0xE4E5F0),
			accent: Rgba.fromHex(0xB1C5FF),
			accentSubtle: Rgba.fromHex(0xB1C5FF).withAlpha(0.18),
			tooltipBg: Rgba.fromHex(0xE4E5F0),
			tooltipText: Rgba.fromHex(0x11121A)
		};
	}

	static function lightShadows():ShadowTokens {
		return {
			shadowSm: [new Shadow(0, 0, 1, 0, Rgba.fromHex(0x161726).withAlpha(0.04)), new Shadow(0, 1, 2, 0, Rgba.fromHex(0x161726).withAlpha(0.06))],
			shadowDefault: [new Shadow(0, 0, 1, 0, Rgba.fromHex(0x161726).withAlpha(0.04)), new Shadow(0, 1, 3, 0, Rgba.fromHex(0x161726).withAlpha(0.06)), new Shadow(0, 2, 6, 0, Rgba.fromHex(0x3D5FE8).withAlpha(0.04))],
			shadowMd: [new Shadow(0, 0, 1, 0, Rgba.fromHex(0x161726).withAlpha(0.05)), new Shadow(0, 2, 4, 0, Rgba.fromHex(0x161726).withAlpha(0.06)), new Shadow(0, 4, 10, 0, Rgba.fromHex(0x3D5FE8).withAlpha(0.05))],
			shadowLg: [new Shadow(0, 0, 1, 0, Rgba.fromHex(0x161726).withAlpha(0.05)), new Shadow(0, 6, 12, 0, Rgba.fromHex(0x161726).withAlpha(0.07)), new Shadow(0, 14, 28, 0, Rgba.fromHex(0x3D5FE8).withAlpha(0.06))],
			shadowXl: [new Shadow(0, 0, 1, 0, Rgba.fromHex(0x161726).withAlpha(0.06)), new Shadow(0, 12, 22, 0, Rgba.fromHex(0x161726).withAlpha(0.08)), new Shadow(0, 28, 48, 0, Rgba.fromHex(0x3D5FE8).withAlpha(0.08))],
			shadow2xl: [new Shadow(0, 0, 2, 0, Rgba.fromHex(0x161726).withAlpha(0.08)), new Shadow(0, 22, 38, 0, Rgba.fromHex(0x161726).withAlpha(0.10)), new Shadow(0, 48, 80, 0, Rgba.fromHex(0x3D5FE8).withAlpha(0.10))],
			shadowInner: [new Shadow(0, 2, 4, 0, Rgba.fromHex(0x161726).withAlpha(0.08))],
			shadowNone: []
		};
	}

	static function darkShadows():ShadowTokens {
		return {
			shadowSm: [new Shadow(0, 0, 1, 0, Rgba.BLACK.withAlpha(0.32)), new Shadow(0, 1, 2, 0, Rgba.BLACK.withAlpha(0.40))],
			shadowDefault: [new Shadow(0, 0, 1, 0, Rgba.BLACK.withAlpha(0.32)), new Shadow(0, 1, 3, 0, Rgba.BLACK.withAlpha(0.40)), new Shadow(0, 2, 6, 0, Rgba.fromHex(0x3D5FE8).withAlpha(0.12))],
			shadowMd: [new Shadow(0, 0, 1, 0, Rgba.BLACK.withAlpha(0.36)), new Shadow(0, 2, 4, 0, Rgba.BLACK.withAlpha(0.42)), new Shadow(0, 4, 10, 0, Rgba.fromHex(0x3D5FE8).withAlpha(0.14))],
			shadowLg: [new Shadow(0, 0, 1, 0, Rgba.BLACK.withAlpha(0.40)), new Shadow(0, 6, 12, 0, Rgba.BLACK.withAlpha(0.46)), new Shadow(0, 14, 28, 0, Rgba.fromHex(0x3D5FE8).withAlpha(0.16))],
			shadowXl: [new Shadow(0, 0, 1, 0, Rgba.BLACK.withAlpha(0.44)), new Shadow(0, 12, 22, 0, Rgba.BLACK.withAlpha(0.52)), new Shadow(0, 28, 48, 0, Rgba.fromHex(0x3D5FE8).withAlpha(0.18))],
			shadow2xl: [new Shadow(0, 0, 2, 0, Rgba.BLACK.withAlpha(0.50)), new Shadow(0, 22, 38, 0, Rgba.BLACK.withAlpha(0.60)), new Shadow(0, 48, 80, 0, Rgba.fromHex(0x3D5FE8).withAlpha(0.22))],
			shadowInner: [new Shadow(0, 2, 4, 0, Rgba.BLACK.withAlpha(0.35))],
			shadowNone: []
		};
	}
}
