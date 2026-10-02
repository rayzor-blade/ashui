package ashui.theme;

/** A corner radius of the theme. **/
@:build(ashui.theme.TokenKeys.build("ashui.theme.RadiusTokens.RadiusTokensData", "Float"))
enum abstract RadiusToken(String) {
	var None = "radiusNone";
	var Sm = "radiusSm";
	var Default = "radiusDefault";
	var Md = "radiusMd";
	var Lg = "radiusLg";
	var Xl = "radiusXl";
	var Xxl = "radius2xl";
	var Xxxl = "radius3xl";
	var Full = "radiusFull";

	public static final ALL:Array<RadiusToken> = [None, Sm, Default, Md, Lg, Xl, Xxl, Xxxl, Full];
}
