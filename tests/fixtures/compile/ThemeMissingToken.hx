// expect: Object requires field tooltipText
class ThemeMissingToken {
	static function main() {
		var c = ashui.theme.ColorTokens.defaults();
		var colors:ashui.theme.ColorTokens.ColorTokensData = {
			primary: c.primary, primaryHover: c.primaryHover, primaryActive: c.primaryActive,
			secondary: c.secondary, secondaryHover: c.secondaryHover, secondaryActive: c.secondaryActive,
			success: c.success, successBg: c.successBg, warning: c.warning, warningBg: c.warningBg,
			error: c.error, errorBg: c.errorBg, info: c.info, infoBg: c.infoBg,
			background: c.background, surface: c.surface, surfaceElevated: c.surfaceElevated, surfaceOverlay: c.surfaceOverlay,
			textPrimary: c.textPrimary, textSecondary: c.textSecondary, textTertiary: c.textTertiary,
			textInverse: c.textInverse, textLink: c.textLink,
			border: c.border, borderSecondary: c.borderSecondary, borderHover: c.borderHover,
			borderFocus: c.borderFocus, borderError: c.borderError,
			inputBg: c.inputBg, inputBgHover: c.inputBgHover, inputBgFocus: c.inputBgFocus, inputBgDisabled: c.inputBgDisabled,
			selection: c.selection, selectionText: c.selectionText,
			accent: c.accent, accentSubtle: c.accentSubtle,
			tooltipBg: c.tooltipBg
		};
		trace(colors);
	}
}
