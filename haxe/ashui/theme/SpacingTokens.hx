package ashui.theme;

typedef SpacingTokensData = {
	final space0:Float;
	final space0_5:Float;
	final space1:Float;
	final space1_5:Float;
	final space2:Float;
	final space2_5:Float;
	final space3:Float;
	final space3_5:Float;
	final space4:Float;
	final space5:Float;
	final space6:Float;
	final space7:Float;
	final space8:Float;
	final space9:Float;
	final space10:Float;
	final space11:Float;
	final space12:Float;
	final space14:Float;
	final space16:Float;
	final space20:Float;
	final space24:Float;
	final space28:Float;
	final space32:Float;
}

/** The theme's spacing scale in pixels, one value per `SpacingToken`. **/
@:forward
abstract SpacingTokens(SpacingTokensData) from SpacingTokensData to SpacingTokensData {
	public inline function get(token:SpacingToken):Float {
		return token.of(this);
	}

	/** Each step as that many multiples of `base`. **/
	public static function withBase(base:Float):SpacingTokens {
		return {
			space0: F32.round(base * 0),
			space0_5: F32.round(base * 0.5),
			space1: F32.round(base * 1),
			space1_5: F32.round(base * 1.5),
			space2: F32.round(base * 2),
			space2_5: F32.round(base * 2.5),
			space3: F32.round(base * 3),
			space3_5: F32.round(base * 3.5),
			space4: F32.round(base * 4),
			space5: F32.round(base * 5),
			space6: F32.round(base * 6),
			space7: F32.round(base * 7),
			space8: F32.round(base * 8),
			space9: F32.round(base * 9),
			space10: F32.round(base * 10),
			space11: F32.round(base * 11),
			space12: F32.round(base * 12),
			space14: F32.round(base * 14),
			space16: F32.round(base * 16),
			space20: F32.round(base * 20),
			space24: F32.round(base * 24),
			space28: F32.round(base * 28),
			space32: F32.round(base * 32)
		};
	}

	/** A 4px base. **/
	public static function defaults():SpacingTokens {
		return withBase(4);
	}
}
