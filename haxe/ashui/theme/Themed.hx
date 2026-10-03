package ashui.theme;

import ashui.reactive.Computed;

/**
	Token values as computeds for binding to a node's properties:

	    node.set(Prop.Background, Themed.brush(Surface));

	Each reads `ThemeState.revision`, so the property follows scheme
	switches, their colour transition and overrides, and nothing else is
	rebuilt. Installs the default theme if none is.
**/
class Themed {
	/** `token`'s colour, its alpha scaled by `alpha`, as Tailwind's `/50` does. **/
	public static function color(token:ColorToken, alpha:Float = 1.0):Computed<ashui.types.Color> {
		var state = ready();
		return Computed.make(() -> {
			state.revision.get();
			scaled(state.color(token), alpha).toColor();
		});
	}

	/** `token`'s colour as a solid fill, its alpha scaled by `alpha`. **/
	public static function brush(token:ColorToken, alpha:Float = 1.0):Computed<ashui.types.Brush> {
		var state = ready();
		return Computed.make(() -> {
			state.revision.get();
			scaled(state.color(token), alpha).toBrush();
		});
	}

	static inline function scaled(c:Rgba, alpha:Float):Rgba
		return alpha == 1.0 ? c : c.withAlpha(c.a * alpha);

	/** `token`'s spacing in pixels. **/
	public static function spacing(token:SpacingToken):Computed<Single> {
		var state = ready();
		return Computed.make(() -> {
			state.revision.get();
			(state.spacingValue(token) : Single);
		});
	}

	/** `token`'s radius on every corner. **/
	public static function radius(token:RadiusToken):Computed<ashui.types.CornerRadius> {
		var state = ready();
		return Computed.make(() -> {
			state.revision.get();
			ashui.types.CornerRadius.all(state.radius(token));
		});
	}

	/** A `Text…` token's font size in pixels. **/
	public static function fontSize(token:TypographyToken):Computed<Single> {
		var state = ready();
		return Computed.make(() -> {
			state.revision.get();
			(state.typography().get(token) : Single);
		});
	}

	/**
		A gradient over the box it fills, coordinates as fractions of it:
		linear from `(x1, y1)` to `(x2, y2)`, or radial about `(x1, y1)` of
		radius `x2`. Each stop is a theme colour at an offset, its alpha
		scaled by `alpha`; the colours follow the theme.
	**/
	public static function gradient(radial:Bool, x1:Float, y1:Float, x2:Float, y2:Float,
			stops:Array<{token:ColorToken, offset:Float, alpha:Float}>):Computed<ashui.types.Brush> {
		var state = ready();
		return Computed.make(() -> {
			state.revision.get();
			var brush = radial ? ashui.types.Brush.radial(x1, y1, x2, true) : ashui.types.Brush.linear(x1, y1, x2, y2, true);
			for (s in stops) {
				var c = state.color(s.token);
				brush.stop(s.offset, c.rgb(), c.a * s.alpha);
			}
			brush;
		});
	}

	/**
		A letter spacing in pixels: `tracking`, a `Tracking…` token in ems,
		times `size`, a `Text…` token's font size.
	**/
	public static function tracking(tracking:TypographyToken, size:TypographyToken):Computed<Single> {
		var state = ready();
		return Computed.make(() -> {
			state.revision.get();
			var t = state.typography();
			(t.get(tracking) * t.get(size) : Single);
		});
	}

	/** A weight token's weight, `FontThin` to `FontBlack`. **/
	public static function fontWeight(token:TypographyToken):Computed<ashui.types.Style.FontWeight> {
		var state = ready();
		return Computed.make(() -> {
			state.revision.get();
			(Std.int(state.typography().get(token)) : ashui.types.Style.FontWeight);
		});
	}

	/** A leading token's line height, as a multiple of the font size. **/
	public static function leading(token:TypographyToken):Computed<Single> {
		var state = ready();
		return Computed.make(() -> {
			state.revision.get();
			(state.typography().get(token) : Single);
		});
	}

	/** `token`'s whole shadow stack; `None` gives one transparent layer. **/
	public static function shadow(token:ShadowToken):Computed<ashui.types.Shadow> {
		var state = ready();
		return Computed.make(() -> {
			state.revision.get();
			var stack = Shadow.toShadowStack(state.shadows().get(token));
			stack != null ? stack : Shadow.none().toShadow();
		});
	}

	/** The installed theme; the default one if none is. Makes its signal before any computed reads it. **/
	static function ready():ThemeState {
		if (ThemeState.tryGet() == null)
			ThemeState.initDefault();
		return ThemeState.get();
	}
}
