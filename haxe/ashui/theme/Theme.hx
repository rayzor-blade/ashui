package ashui.theme;

/**
	One scheme of a theme, light or dark: every token family. A token is a
	named design value, a colour such as `ColorToken.Primary`, a spacing
	step, a radius, that UI code refers to by name rather than writing the
	value; the theme supplies the values, so a theme or scheme change
	restyles everything that uses them. `ThemeState` holds the one in use;
	`Themed` and `tw` classes bind properties to its tokens.

	A theme that does not smooth corners leaves `shape` out and gets
	`ShapeTokens.OFF`. Mirrors Blinc's `Theme` trait.
**/
@:structInit
final class Theme {
	public final name:String;
	public final colorScheme:ColorScheme;
	public final colors:ColorTokens;
	public final typography:TypographyTokens;
	public final spacing:SpacingTokens;
	public final radii:RadiusTokens;
	public final shape:ShapeTokens;
	public final shadows:ShadowTokens;
	public final animations:AnimationTokens;

	public function new(name:String, colorScheme:ColorScheme, colors:ColorTokens, typography:TypographyTokens, spacing:SpacingTokens,
			radii:RadiusTokens, shadows:ShadowTokens, animations:AnimationTokens, ?shape:ShapeTokens) {
		this.name = name;
		this.colorScheme = colorScheme;
		this.colors = colors;
		this.typography = typography;
		this.spacing = spacing;
		this.radii = radii;
		this.shape = shape != null ? shape : ShapeTokens.OFF;
		this.shadows = shadows;
		this.animations = animations;
	}
}
