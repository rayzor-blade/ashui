package ashui.theme;

typedef ColorTokensData = {
	final primary:Rgba;
	final primaryHover:Rgba;
	final primaryActive:Rgba;
	final secondary:Rgba;
	final secondaryHover:Rgba;
	final secondaryActive:Rgba;
	final success:Rgba;
	final successBg:Rgba;
	final warning:Rgba;
	final warningBg:Rgba;
	final error:Rgba;
	final errorBg:Rgba;
	final info:Rgba;
	final infoBg:Rgba;
	final background:Rgba;
	final surface:Rgba;
	final surfaceElevated:Rgba;
	final surfaceOverlay:Rgba;
	final textPrimary:Rgba;
	final textSecondary:Rgba;
	final textTertiary:Rgba;
	final textInverse:Rgba;
	final textLink:Rgba;
	final border:Rgba;
	final borderSecondary:Rgba;
	final borderHover:Rgba;
	final borderFocus:Rgba;
	final borderError:Rgba;
	final inputBg:Rgba;
	final inputBgHover:Rgba;
	final inputBgFocus:Rgba;
	final inputBgDisabled:Rgba;
	final selection:Rgba;
	final selectionText:Rgba;
	final accent:Rgba;
	final accentSubtle:Rgba;
	final tooltipBg:Rgba;
	final tooltipText:Rgba;
}

/** The theme's colours, one per `ColorToken`. **/
@:forward
abstract ColorTokens(ColorTokensData) from ColorTokensData to ColorTokensData {
	public inline function get(token:ColorToken):Rgba {
		return token.of(this);
	}

	/** Each colour from `from` to `to` by `t`. **/
	public static function lerp(from:ColorTokens, to:ColorTokens, t:Float):ColorTokens {
		return {
			primary: Rgba.lerp(from.primary, to.primary, t),
			primaryHover: Rgba.lerp(from.primaryHover, to.primaryHover, t),
			primaryActive: Rgba.lerp(from.primaryActive, to.primaryActive, t),
			secondary: Rgba.lerp(from.secondary, to.secondary, t),
			secondaryHover: Rgba.lerp(from.secondaryHover, to.secondaryHover, t),
			secondaryActive: Rgba.lerp(from.secondaryActive, to.secondaryActive, t),
			success: Rgba.lerp(from.success, to.success, t),
			successBg: Rgba.lerp(from.successBg, to.successBg, t),
			warning: Rgba.lerp(from.warning, to.warning, t),
			warningBg: Rgba.lerp(from.warningBg, to.warningBg, t),
			error: Rgba.lerp(from.error, to.error, t),
			errorBg: Rgba.lerp(from.errorBg, to.errorBg, t),
			info: Rgba.lerp(from.info, to.info, t),
			infoBg: Rgba.lerp(from.infoBg, to.infoBg, t),
			background: Rgba.lerp(from.background, to.background, t),
			surface: Rgba.lerp(from.surface, to.surface, t),
			surfaceElevated: Rgba.lerp(from.surfaceElevated, to.surfaceElevated, t),
			surfaceOverlay: Rgba.lerp(from.surfaceOverlay, to.surfaceOverlay, t),
			textPrimary: Rgba.lerp(from.textPrimary, to.textPrimary, t),
			textSecondary: Rgba.lerp(from.textSecondary, to.textSecondary, t),
			textTertiary: Rgba.lerp(from.textTertiary, to.textTertiary, t),
			textInverse: Rgba.lerp(from.textInverse, to.textInverse, t),
			textLink: Rgba.lerp(from.textLink, to.textLink, t),
			border: Rgba.lerp(from.border, to.border, t),
			borderSecondary: Rgba.lerp(from.borderSecondary, to.borderSecondary, t),
			borderHover: Rgba.lerp(from.borderHover, to.borderHover, t),
			borderFocus: Rgba.lerp(from.borderFocus, to.borderFocus, t),
			borderError: Rgba.lerp(from.borderError, to.borderError, t),
			inputBg: Rgba.lerp(from.inputBg, to.inputBg, t),
			inputBgHover: Rgba.lerp(from.inputBgHover, to.inputBgHover, t),
			inputBgFocus: Rgba.lerp(from.inputBgFocus, to.inputBgFocus, t),
			inputBgDisabled: Rgba.lerp(from.inputBgDisabled, to.inputBgDisabled, t),
			selection: Rgba.lerp(from.selection, to.selection, t),
			selectionText: Rgba.lerp(from.selectionText, to.selectionText, t),
			accent: Rgba.lerp(from.accent, to.accent, t),
			accentSubtle: Rgba.lerp(from.accentSubtle, to.accentSubtle, t),
			tooltipBg: Rgba.lerp(from.tooltipBg, to.tooltipBg, t),
			tooltipText: Rgba.lerp(from.tooltipText, to.tooltipText, t)
		};
	}

	/** The default theme's light colours. **/
	public static function defaults():ColorTokens {
		return ashui.theme.themes.HybridTheme.light().colors;
	}
}
