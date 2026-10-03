package ashui.theme;

typedef RadiusTokensData = {
	final radiusNone:Float;
	final radiusSm:Float;
	final radiusDefault:Float;
	final radiusMd:Float;
	final radiusLg:Float;
	final radiusXl:Float;
	final radius2xl:Float;
	final radius3xl:Float;
	final radiusFull:Float;
}

/**
	The theme's corner radii in pixels, one per `RadiusToken`. `radiusDefault`
	is what an unmarked surface gets, not a step of the ladder: themes set it
	at their squircle threshold so default surfaces are smoothed.
**/
@:forward
abstract RadiusTokens(RadiusTokensData) from RadiusTokensData to RadiusTokensData {
	/** `token`'s radius in pixels. **/
	public inline function get(token:RadiusToken):Float {
		return token.of(this);
	}

	/** Tailwind's radius scale. **/
	public static function defaults():RadiusTokens {
		return {
			radiusNone: 0,
			radiusSm: 2,
			radiusDefault: 4,
			radiusMd: 6,
			radiusLg: 8,
			radiusXl: 12,
			radius2xl: 16,
			radius3xl: 24,
			radiusFull: 9999
		};
	}
}
