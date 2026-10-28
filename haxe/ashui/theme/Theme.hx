package ashui.theme;

/**
	Defines the design tokens for one light or dark color scheme.
	Tokens name reusable values such as colors, spacing and corner radii.
	`ThemeState` selects the active theme. `Themed` bindings and `tw` classes
	use its tokens, so changing the theme updates the UI.

	Omit `shape` to use `ShapeTokens.OFF`, which disables corner smoothing.
	This type corresponds to Blinc's `Theme` trait.
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

	public function new(name:String, colorScheme:ColorScheme, colors:ColorTokens, typography:TypographyTokens, spacing:SpacingTokens, radii:RadiusTokens,
			shadows:ShadowTokens, animations:AnimationTokens, ?shape:ShapeTokens) {
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
