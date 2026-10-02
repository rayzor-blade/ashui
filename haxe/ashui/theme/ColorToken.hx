package ashui.theme;

/** A semantic colour of the theme. **/
@:build(ashui.theme.TokenKeys.build("ashui.theme.ColorTokens.ColorTokensData", "ashui.theme.Rgba"))
enum abstract ColorToken(String) {
	var Primary = "primary";
	var PrimaryHover = "primaryHover";
	var PrimaryActive = "primaryActive";
	var Secondary = "secondary";
	var SecondaryHover = "secondaryHover";
	var SecondaryActive = "secondaryActive";
	var Success = "success";
	var SuccessBg = "successBg";
	var Warning = "warning";
	var WarningBg = "warningBg";
	var Error = "error";
	var ErrorBg = "errorBg";
	var Info = "info";
	var InfoBg = "infoBg";
	var Background = "background";
	var Surface = "surface";
	var SurfaceElevated = "surfaceElevated";
	var SurfaceOverlay = "surfaceOverlay";
	var TextPrimary = "textPrimary";
	var TextSecondary = "textSecondary";
	var TextTertiary = "textTertiary";
	var TextInverse = "textInverse";
	var TextLink = "textLink";
	var Border = "border";
	var BorderSecondary = "borderSecondary";
	var BorderHover = "borderHover";
	var BorderFocus = "borderFocus";
	var BorderError = "borderError";
	var InputBg = "inputBg";
	var InputBgHover = "inputBgHover";
	var InputBgFocus = "inputBgFocus";
	var InputBgDisabled = "inputBgDisabled";
	var Selection = "selection";
	var SelectionText = "selectionText";
	var Accent = "accent";
	var AccentSubtle = "accentSubtle";
	var TooltipBackground = "tooltipBg";
	var TooltipText = "tooltipText";

	/** Every colour token, in declaration order. **/
	public static final ALL:Array<ColorToken> = [Primary, PrimaryHover, PrimaryActive, Secondary, SecondaryHover, SecondaryActive, Success, SuccessBg, Warning, WarningBg, Error, ErrorBg, Info, InfoBg, Background, Surface, SurfaceElevated, SurfaceOverlay, TextPrimary, TextSecondary, TextTertiary, TextInverse, TextLink, Border, BorderSecondary, BorderHover, BorderFocus, BorderError, InputBg, InputBgHover, InputBgFocus, InputBgDisabled, Selection, SelectionText, Accent, AccentSubtle, TooltipBackground, TooltipText];
}
