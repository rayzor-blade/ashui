package ashui.animation;

import ashui.layout.PropertyId;
import ashui.theme.AnimationToken;
import ashui.theme.EasingToken;
import ashui.theme.ThemeState;

/**
	Defines which node properties animate when their values change, with a
	duration and easing curve. This corresponds to a CSS `transition`.
	Omitted settings use the theme's fast duration and default easing.

	Set the transition before the properties it covers. Tailwind-style
	`transition` classes create these definitions automatically.
**/
class Transition {
	/** Background, border and text colours. **/
	public static final COLORS:Array<PropertyId> = [Background, BorderColor, Color, AccentColor];

	/** Tailwind's default set: colours, opacity, shadow and transform. **/
	public static final DEFAULT:Array<PropertyId> = COLORS.concat([Opacity, Shadow, Transform]);

	/** Everything that can move between two values. **/
	public static final ALL:Array<PropertyId> = DEFAULT.concat([
		Width,
		Height,
		MinWidth,
		MaxWidth,
		MinHeight,
		MaxHeight,
		Padding,
		Margin,
		Gap,
		Top,
		Right,
		Bottom,
		Left,
		BorderWidth,
		CornerRadius,
		FontSize,
		LetterSpacing,
		LineHeight,
		FlexGrow,
		FlexShrink,
		FlexBasis,
		PaddingTop,
		PaddingRight,
		PaddingBottom,
		PaddingLeft,
		MarginTop,
		MarginRight,
		MarginBottom,
		MarginLeft,
		GapX,
		GapY,
		WidthPercent,
		HeightPercent,
		MinWidthPercent,
		MaxWidthPercent,
		MinHeightPercent,
		MaxHeightPercent,
		FlexBasisPercent
	]);

	public final properties:Array<PropertyId>;

	final duration:Null<AnimationToken>;
	final milliseconds:Null<Int>;
	final easing:Null<EasingToken>;
	final fixedCurve:Null<ashui.theme.Easing>;
	final delayMilliseconds:Int;

	/** `duration` as a theme token, or `milliseconds`; the curve as a theme token, or `curve`. **/
	public function new(properties:Array<PropertyId>, ?duration:AnimationToken, ?milliseconds:Int, ?easing:EasingToken, ?curve:ashui.theme.Easing, delay = 0) {
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

	/** The transition `prop` moves by; this one, unless timings differ by property, as CSS's can. **/
	public function forProperty(prop:PropertyId):Transition
		return this;

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
