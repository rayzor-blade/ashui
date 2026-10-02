// expect: Nowhere names "nowhere", which ashui.theme.RadiusTokens.RadiusTokensData has no field for
@:build(ashui.theme.TokenKeys.build("ashui.theme.RadiusTokens.RadiusTokensData", "Float"))
enum abstract BadRadius(String) {
	var None = "radiusNone";
	var Sm = "radiusSm";
	var Default = "radiusDefault";
	var Md = "radiusMd";
	var Lg = "radiusLg";
	var Xl = "radiusXl";
	var Xxl = "radius2xl";
	var Xxxl = "radius3xl";
	var Full = "radiusFull";
	var Nowhere = "nowhere";
}

class TokenWithoutField {
	static function main() {
		trace(BadRadius.Sm.of(ashui.theme.RadiusTokens.defaults()));
	}
}
