package ashui.theme;

import ashui.reactive.Computed;

/**
	Token values as computeds for binding to properties: each reads
	`ThemeState.revision`, so the property follows scheme switches, their
	colour transition and overrides, and nothing else is rebuilt. Installs
	the default theme if none is.
**/
class Themed {
	public static function color(token:ColorToken):Computed<ashui.types.Color> {
		var state = ready();
		return Computed.make(() -> {
			state.revision.get();
			state.color(token).toColor();
		});
	}

	/** `token`'s colour as a solid fill. **/
	public static function brush(token:ColorToken):Computed<ashui.types.Brush> {
		var state = ready();
		return Computed.make(() -> {
			state.revision.get();
			state.color(token).toBrush();
		});
	}

	public static function spacing(token:SpacingToken):Computed<Single> {
		var state = ready();
		return Computed.make(() -> {
			state.revision.get();
			(state.spacingValue(token) : Single);
		});
	}

	public static function radius(token:RadiusToken):Computed<ashui.types.CornerRadius> {
		var state = ready();
		return Computed.make(() -> {
			state.revision.get();
			ashui.types.CornerRadius.all(state.radius(token));
		});
	}

	public static function fontSize(token:TypographyToken):Computed<Single> {
		var state = ready();
		return Computed.make(() -> {
			state.revision.get();
			(state.typography().get(token) : Single);
		});
	}

	/** The broadest layer of `token`'s shadow stack; a node draws one layer yet. **/
	public static function shadow(token:ShadowToken):Computed<ashui.types.Shadow> {
		var state = ready();
		return Computed.make(() -> {
			state.revision.get();
			var stack = state.shadows().get(token);
			(stack.length == 0 ? Shadow.none() : stack[stack.length - 1]).toShadow();
		});
	}

	/** The installed theme; the default one if none is. Makes its signal before any computed reads it. **/
	static function ready():ThemeState {
		if (ThemeState.tryGet() == null)
			ThemeState.initDefault();
		return ThemeState.get();
	}
}
