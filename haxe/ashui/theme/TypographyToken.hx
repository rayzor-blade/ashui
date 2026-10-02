package ashui.theme;

/** A size, weight, line height or letter spacing of the theme. **/
enum abstract TypographyToken(Int) {
	var TextXs;
	var TextSm;
	var TextBase;
	var TextLg;
	var TextXl;
	var Text2xl;
	var Text3xl;
	var Text4xl;
	var Text5xl;

	var FontThin;
	var FontLight;
	var FontNormal;
	var FontMedium;
	var FontSemibold;
	var FontBold;
	var FontBlack;

	var LeadingNone;
	var LeadingTight;
	var LeadingSnug;
	var LeadingNormal;
	var LeadingRelaxed;
	var LeadingLoose;

	var TrackingTighter;
	var TrackingTight;
	var TrackingNormal;
	var TrackingWide;
	var TrackingWider;
}
