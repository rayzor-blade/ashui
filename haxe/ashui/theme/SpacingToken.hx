package ashui.theme;

/** A step of the theme's spacing scale. **/
@:build(ashui.theme.TokenKeys.build("ashui.theme.SpacingTokens.SpacingTokensData", "Float"))
enum abstract SpacingToken(String) {
	var Space0 = "space0";
	var Space0_5 = "space0_5";
	var Space1 = "space1";
	var Space1_5 = "space1_5";
	var Space2 = "space2";
	var Space2_5 = "space2_5";
	var Space3 = "space3";
	var Space3_5 = "space3_5";
	var Space4 = "space4";
	var Space5 = "space5";
	var Space6 = "space6";
	var Space7 = "space7";
	var Space8 = "space8";
	var Space9 = "space9";
	var Space10 = "space10";
	var Space11 = "space11";
	var Space12 = "space12";
	var Space14 = "space14";
	var Space16 = "space16";
	var Space20 = "space20";
	var Space24 = "space24";
	var Space28 = "space28";
	var Space32 = "space32";

	public static final ALL:Array<SpacingToken> = [Space0, Space0_5, Space1, Space1_5, Space2, Space2_5, Space3, Space3_5, Space4, Space5, Space6, Space7, Space8, Space9, Space10, Space11, Space12, Space14, Space16, Space20, Space24, Space28, Space32];
}
