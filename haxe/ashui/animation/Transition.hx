package ashui.animation;

import ashui.layout.PropertyId;
import ashui.theme.AnimationToken;
import ashui.theme.EasingToken;
import ashui.theme.ThemeState;

/**
	Which properties of a node animate when their value changes, for how
	long and along which curve, as a CSS `transition` says. A duration or a
	curve left out is the theme's: its fast duration and its default curve.
	Set on a node before the properties it covers; `tw`'s `transition`
	classes make one.
**/
class Transition {
	/** Background, border and text colours. **/
	public static final COLORS:Array<PropertyId> = [Background, BorderColor, Color, AccentColor];

	/** Tailwind's default set: colours, opacity, shadow and transform. **/
	public static final DEFAULT:Array<PropertyId> = COLORS.concat([Opacity, Shadow, Transform]);

	/** Everything that can move between two values. **/
	public static final ALL:Array<PropertyId> = DEFAULT.concat([
		Width, Height, MinWidth, MaxWidth, MinHeight, MaxHeight, Padding, Margin, Gap, Top, Right, Bottom, Left, BorderWidth, CornerRadius, FontSize,
		LetterSpacing, LineHeight, FlexGrow, FlexShrink, FlexBasis, PaddingTop, PaddingRight, PaddingBottom, PaddingLeft, MarginTop, MarginRight,
		MarginBottom, MarginLeft, GapX, GapY, WidthPercent, HeightPercent, MinWidthPercent, MaxWidthPercent, MinHeightPercent, MaxHeightPercent,
		FlexBasisPercent
	]);

	public final properties:Array<PropertyId>;
	final duration:Null<AnimationToken>;
	final milliseconds:Null<Int>;
	final easing:Null<EasingToken>;
	final fixedCurve:Null<ashui.theme.Easing>;
	final delayMilliseconds:Int;

	/** `duration` as a theme token, or `milliseconds`; the curve as a theme token, or `curve`. **/
	public function new(properties:Array<PropertyId>, ?duration:AnimationToken, ?milliseconds:Int, ?easing:EasingToken, ?curve:ashui.theme.Easing,
			delay = 0) {
		this.properties = properties;
		this.duration = duration;
		this.milliseconds = milliseconds;
		this.easing = easing;
		this.fixedCurve = curve;
		this.delayMilliseconds = delay;
	}

	public inline function covers(prop:PropertyId):Bool {
		return properties.indexOf(prop) >= 0;
	}

	/** Seconds, from the installed theme when given as a token. **/
	public function seconds():Float {
		if (milliseconds != null)
			return milliseconds / 1000;
		var theme = ThemeState.tryGet();
		var animations = theme != null ? theme.animations() : ashui.theme.AnimationTokens.defaults();
		return (duration != null ? animations.get(duration) : animations.durationFast) / 1000;
	}

	public function delay():Float {
		return delayMilliseconds / 1000;
	}

	public function curve():ashui.theme.Easing {
		if (fixedCurve != null)
			return fixedCurve;
		var theme = ThemeState.tryGet();
		var animations = theme != null ? theme.animations() : ashui.theme.AnimationTokens.defaults();
		return (easing != null ? easing : EasingToken.Default).of(animations);
	}
}
