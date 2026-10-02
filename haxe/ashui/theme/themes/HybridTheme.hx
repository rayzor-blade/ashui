package ashui.theme.themes;

import ashui.theme.*;

/** Universal HID · Hybrid: between Restrained's Apple-leaning calm and Expressive's Material-leaning colour. Blinc's and ashui's default theme. **/
class HybridTheme {
	public static inline var NAME = "Universal · Hybrid";

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
			radiusDefault: 12,
			radiusMd: 10,
			radiusLg: 14,
			radiusXl: 18,
			radius2xl: 24,
			radius3xl: 32,
			radiusFull: 9999
		};
	}

	public static function shape():ShapeTokens {
		return new ShapeTokens(0.4, 3.3, 12);
	}

	public static function animations():AnimationTokens {
		return {
			durationFastest: 80,
			durationFaster: 120,
			durationFast: 180,
			durationNormal: 240,
			durationSlow: 320,
			durationSlower: 420,
			durationSlowest: 540,
			easeDefault: Universal.STANDARD,
			easeIn: EaseIn,
			easeOut: EaseOut,
			easeInOut: EaseInOut,
			easeState: Universal.STANDARD,
			easeNav: Universal.HYBRID_NAV,
			easeSpring: Universal.HYBRID_SPRING,
			easeSheet: Universal.HYBRID_NAV
		};
	}

	static function lightColors():ColorTokens {
		return {
			primary: Rgba.fromHex(0x2A63E9),
			primaryHover: Rgba.fromHex(0x1F52D1),
			primaryActive: Rgba.fromHex(0x1846B5),
			secondary: Rgba.fromHex(0x605C73),
			secondaryHover: Rgba.fromHex(0x4B475C),
			secondaryActive: Rgba.fromHex(0x3A3748),
			success: Rgba.fromHex(0x16A34A),
			successBg: Rgba.fromHex(0x16A34A).withAlpha(0.12),
			warning: Rgba.fromHex(0xD97706),
			warningBg: Rgba.fromHex(0xD97706).withAlpha(0.12),
			error: Rgba.fromHex(0xDC2626),
			errorBg: Rgba.fromHex(0xDC2626).withAlpha(0.12),
			info: Rgba.fromHex(0x1283C7),
			infoBg: Rgba.fromHex(0x1283C7).withAlpha(0.12),
			background: Rgba.fromHex(0xF6F8FC),
			surface: Rgba.WHITE,
			surfaceElevated: Rgba.fromHex(0xFBFCFE),
			surfaceOverlay: Rgba.fromHex(0xE7ECF6),
			textPrimary: Rgba.fromHex(0x0F1422),
			textSecondary: Rgba.fromHex(0x525A6E),
			textTertiary: Rgba.fromHex(0x8F95A6),
			textInverse: Rgba.WHITE,
			textLink: Rgba.fromHex(0x2A63E9),
			border: Rgba.fromHex(0x0F1422).withAlpha(0.10),
			borderSecondary: Rgba.fromHex(0xD4D9E4),
			borderHover: Rgba.fromHex(0x0F1422).withAlpha(0.16),
			borderFocus: Rgba.fromHex(0x2A63E9),
			borderError: Rgba.fromHex(0xC7382D),
			inputBg: Rgba.WHITE,
			inputBgHover: Rgba.fromHex(0xF8FAFD),
			inputBgFocus: Rgba.WHITE,
			inputBgDisabled: Rgba.fromHex(0xEEF0F6),
			selection: Rgba.fromHex(0x2A63E9).withAlpha(0.24),
			selectionText: Rgba.fromHex(0x0F1422),
			accent: Rgba.fromHex(0x2A63E9),
			accentSubtle: Rgba.fromHex(0xE6EEFE),
			tooltipBg: Rgba.fromHex(0x161A28),
			tooltipText: Rgba.fromHex(0xF6F8FC)
		};
	}

	static function darkColors():ColorTokens {
		return {
			primary: Rgba.fromHex(0x7DA8FF),
			primaryHover: Rgba.fromHex(0x94B8FF),
			primaryActive: Rgba.fromHex(0xACC8FF),
			secondary: Rgba.fromHex(0xA8A4B8),
			secondaryHover: Rgba.fromHex(0xBFBBCC),
			secondaryActive: Rgba.fromHex(0xD6D3E0),
			success: Rgba.fromHex(0x54D281),
			successBg: Rgba.fromHex(0x54D281).withAlpha(0.15),
			warning: Rgba.fromHex(0xF0B14B),
			warningBg: Rgba.fromHex(0xF0B14B).withAlpha(0.15),
			error: Rgba.fromHex(0xFF6F5F),
			errorBg: Rgba.fromHex(0xFF6F5F).withAlpha(0.15),
			info: Rgba.fromHex(0x6BC0EE),
			infoBg: Rgba.fromHex(0x6BC0EE).withAlpha(0.15),
			background: Rgba.fromHex(0x0F1320),
			surface: Rgba.fromHex(0x1A1F2E),
			surfaceElevated: Rgba.fromHex(0x232940),
			surfaceOverlay: Rgba.fromHex(0x0A0D17),
			textPrimary: Rgba.fromHex(0xECEEF4),
			textSecondary: Rgba.fromHex(0xADB3C2),
			textTertiary: Rgba.fromHex(0x737A8C),
			textInverse: Rgba.fromHex(0x0F1320),
			textLink: Rgba.fromHex(0x7DA8FF),
			border: Rgba.WHITE.withAlpha(0.10),
			borderSecondary: Rgba.fromHex(0x3A4055),
			borderHover: Rgba.WHITE.withAlpha(0.18),
			borderFocus: Rgba.fromHex(0x7DA8FF),
			borderError: Rgba.fromHex(0xFF6F5F),
			inputBg: Rgba.fromHex(0x1A1F2E),
			inputBgHover: Rgba.fromHex(0x222740),
			inputBgFocus: Rgba.fromHex(0x1A1F2E),
			inputBgDisabled: Rgba.fromHex(0x13172A),
			selection: Rgba.fromHex(0x7DA8FF).withAlpha(0.32),
			selectionText: Rgba.fromHex(0xECEEF4),
			accent: Rgba.fromHex(0x7DA8FF),
			accentSubtle: Rgba.fromHex(0x7DA8FF).withAlpha(0.16),
			tooltipBg: Rgba.fromHex(0xECEEF4),
			tooltipText: Rgba.fromHex(0x0F1320)
		};
	}

	static function lightShadows():ShadowTokens {
		return {
			shadowSm: [new Shadow(0, 0, 1, 0, Rgba.fromHex(0x0F1422).withAlpha(0.05)), new Shadow(0, 1, 2, 0, Rgba.fromHex(0x0F1422).withAlpha(0.06))],
			shadowDefault: [new Shadow(0, 1, 1, 0, Rgba.fromHex(0x0F1422).withAlpha(0.05)), new Shadow(0, 2, 4, 0, Rgba.fromHex(0x0F1422).withAlpha(0.06))],
			shadowMd: [new Shadow(0, 1, 2, 0, Rgba.fromHex(0x0F1422).withAlpha(0.05)), new Shadow(0, 4, 8, 0, Rgba.fromHex(0x0F1422).withAlpha(0.07))],
			shadowLg: [new Shadow(0, 3, 6, 0, Rgba.fromHex(0x0F1422).withAlpha(0.06)), new Shadow(0, 12, 22, 0, Rgba.fromHex(0x0F1422).withAlpha(0.08))],
			shadowXl: [new Shadow(0, 6, 12, 0, Rgba.fromHex(0x0F1422).withAlpha(0.07)), new Shadow(0, 24, 40, 0, Rgba.fromHex(0x0F1422).withAlpha(0.10))],
			shadow2xl: [new Shadow(0, 10, 20, 0, Rgba.fromHex(0x0F1422).withAlpha(0.09)), new Shadow(0, 40, 64, 0, Rgba.fromHex(0x0F1422).withAlpha(0.14))],
			shadowInner: [new Shadow(0, 1, 2, 0, Rgba.fromHex(0x0F1422).withAlpha(0.07))],
			shadowNone: []
		};
	}

	static function darkShadows():ShadowTokens {
		return {
			shadowSm: [new Shadow(0, 0, 1, 0, Rgba.BLACK.withAlpha(0.22)), new Shadow(0, 1, 2, 0, Rgba.BLACK.withAlpha(0.35))],
			shadowDefault: [new Shadow(0, 1, 1, 0, Rgba.BLACK.withAlpha(0.26)), new Shadow(0, 2, 4, 0, Rgba.BLACK.withAlpha(0.40))],
			shadowMd: [new Shadow(0, 1, 2, 0, Rgba.BLACK.withAlpha(0.28)), new Shadow(0, 4, 8, 0, Rgba.BLACK.withAlpha(0.42))],
			shadowLg: [new Shadow(0, 3, 6, 0, Rgba.BLACK.withAlpha(0.30)), new Shadow(0, 12, 22, 0, Rgba.BLACK.withAlpha(0.44))],
			shadowXl: [new Shadow(0, 6, 12, 0, Rgba.BLACK.withAlpha(0.34)), new Shadow(0, 24, 40, 0, Rgba.BLACK.withAlpha(0.50))],
			shadow2xl: [new Shadow(0, 10, 20, 0, Rgba.BLACK.withAlpha(0.40)), new Shadow(0, 40, 64, 0, Rgba.BLACK.withAlpha(0.58))],
			shadowInner: [new Shadow(0, 1, 2, 0, Rgba.BLACK.withAlpha(0.32))],
			shadowNone: []
		};
	}
}
