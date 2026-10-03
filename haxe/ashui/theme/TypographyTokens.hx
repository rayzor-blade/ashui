package ashui.theme;

typedef TypographyTokensData = {
	final fontSans:FontFamily;
	final fontSerif:FontFamily;
	final fontMono:FontFamily;

	/** Font sizes in pixels. **/
	final textXs:Float;
	final textSm:Float;
	final textBase:Float;
	final textLg:Float;
	final textXl:Float;
	final text2xl:Float;
	final text3xl:Float;
	final text4xl:Float;
	final text5xl:Float;

	final fontThin:FontWeight;
	final fontLight:FontWeight;
	final fontNormal:FontWeight;
	final fontMedium:FontWeight;
	final fontSemibold:FontWeight;
	final fontBold:FontWeight;
	final fontBlack:FontWeight;

	/** Line heights as multiples of the font size. **/
	final leadingNone:Float;
	final leadingTight:Float;
	final leadingSnug:Float;
	final leadingNormal:Float;
	final leadingRelaxed:Float;
	final leadingLoose:Float;

	/** Letter spacing in ems. **/
	final trackingTighter:Float;
	final trackingTight:Float;
	final trackingNormal:Float;
	final trackingWide:Float;
	final trackingWider:Float;
}

/** The theme's type: families, sizes, weights, line heights and letter spacing. **/
@:forward
abstract TypographyTokens(TypographyTokensData) from TypographyTokensData to TypographyTokensData {
	/** `token`'s value; a weight as its number. **/
	public function get(token:TypographyToken):Float {
		return switch token {
			case TextXs: this.textXs;
			case TextSm: this.textSm;
			case TextBase: this.textBase;
			case TextLg: this.textLg;
			case TextXl: this.textXl;
			case Text2xl: this.text2xl;
			case Text3xl: this.text3xl;
			case Text4xl: this.text4xl;
			case Text5xl: this.text5xl;
			case FontThin: this.fontThin;
			case FontLight: this.fontLight;
			case FontNormal: this.fontNormal;
			case FontMedium: this.fontMedium;
			case FontSemibold: this.fontSemibold;
			case FontBold: this.fontBold;
			case FontBlack: this.fontBlack;
			case LeadingNone: this.leadingNone;
			case LeadingTight: this.leadingTight;
			case LeadingSnug: this.leadingSnug;
			case LeadingNormal: this.leadingNormal;
			case LeadingRelaxed: this.leadingRelaxed;
			case LeadingLoose: this.leadingLoose;
			case TrackingTighter: this.trackingTighter;
			case TrackingTight: this.trackingTight;
			case TrackingNormal: this.trackingNormal;
			case TrackingWide: this.trackingWide;
			case TrackingWider: this.trackingWider;
		}
	}

	/** System font stacks on a Tailwind-like size scale: what a theme starts from. **/
	public static function defaults():TypographyTokens {
		return {
			fontSans: FontFamily.systemSans(),
			fontSerif: FontFamily.systemSerif(),
			fontMono: FontFamily.systemMono(),
			textXs: 12,
			textSm: 14,
			textBase: 16,
			textLg: 18,
			textXl: 20,
			text2xl: 24,
			text3xl: 30,
			text4xl: 36,
			text5xl: 48,
			fontThin: Thin,
			fontLight: Light,
			fontNormal: Normal,
			fontMedium: Medium,
			fontSemibold: Semibold,
			fontBold: Bold,
			fontBlack: Black,
			leadingNone: 1.0,
			leadingTight: F32.round(1.25),
			leadingSnug: F32.round(1.375),
			leadingNormal: F32.round(1.5),
			leadingRelaxed: F32.round(1.625),
			leadingLoose: 2.0,
			trackingTighter: F32.round(-0.05),
			trackingTight: F32.round(-0.025),
			trackingNormal: 0,
			trackingWide: F32.round(0.025),
			trackingWider: F32.round(0.05)
		};
	}

	/** These tokens with the given fields replaced. **/
	public function with(changes:Dynamic):TypographyTokens {
		var copy:Dynamic = Reflect.copy(this);
		for (field in Reflect.fields(changes))
			Reflect.setField(copy, field, Reflect.field(changes, field));
		return copy;
	}
}
