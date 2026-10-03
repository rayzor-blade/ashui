package ashui.theme;

typedef ShadowTokensData = {
	final shadowSm:Array<Shadow>;
	final shadowDefault:Array<Shadow>;
	final shadowMd:Array<Shadow>;
	final shadowLg:Array<Shadow>;
	final shadowXl:Array<Shadow>;
	final shadow2xl:Array<Shadow>;
	final shadowInner:Array<Shadow>;
	final shadowNone:Array<Shadow>;
}

/** The theme's shadow stacks by elevation; a stack is drawn last layer first. **/
@:forward
abstract ShadowTokens(ShadowTokensData) from ShadowTokensData to ShadowTokensData {
	public function get(token:ShadowToken):Array<Shadow> {
		return switch token {
			case Sm: this.shadowSm;
			case Default: this.shadowDefault;
			case Md: this.shadowMd;
			case Lg: this.shadowLg;
			case Xl: this.shadowXl;
			case Xxl: this.shadow2xl;
			// `shadow-inner` is cast inside the box whatever its layers say.
			case Inner: [for (s in this.shadowInner) s.inside()];
			case None: this.shadowNone;
		}
	}

	public static inline function single(shadow:Shadow):Array<Shadow> {
		return [shadow];
	}

	/** Blinc's single-layer black shadows for light surfaces. **/
	public static function light():ShadowTokens {
		return ladder([0.05, 0.1, 0.1, 0.1, 0.1, 0.25, 0.05]);
	}

	/** The same shadows, stronger, for dark surfaces. **/
	public static function dark():ShadowTokens {
		return ladder([0.2, 0.3, 0.3, 0.3, 0.3, 0.5, 0.15]);
	}

	/** sm, default, md, lg, xl, 2xl and inner at the given alphas. **/
	static function ladder(alpha:Array<Float>):ShadowTokens {
		function layer(y:Float, blur:Float, spread:Float, a:Float)
			return [new Shadow(0, y, blur, spread, Rgba.BLACK.withAlpha(a))];
		return {
			shadowSm: layer(1, 2, 0, alpha[0]),
			shadowDefault: layer(1, 3, 0, alpha[1]),
			shadowMd: layer(4, 6, -1, alpha[2]),
			shadowLg: layer(10, 15, -3, alpha[3]),
			shadowXl: layer(20, 25, -5, alpha[4]),
			shadow2xl: layer(25, 50, -12, alpha[5]),
			shadowInner: layer(2, 4, 0, alpha[6]),
			shadowNone: []
		};
	}

	/** Each stack from `from` to `to` by `t`; `shadowNone` stays empty. **/
	public static function lerp(from:ShadowTokens, to:ShadowTokens, t:Float):ShadowTokens {
		return {
			shadowSm: Shadow.lerpStack(from.shadowSm, to.shadowSm, t),
			shadowDefault: Shadow.lerpStack(from.shadowDefault, to.shadowDefault, t),
			shadowMd: Shadow.lerpStack(from.shadowMd, to.shadowMd, t),
			shadowLg: Shadow.lerpStack(from.shadowLg, to.shadowLg, t),
			shadowXl: Shadow.lerpStack(from.shadowXl, to.shadowXl, t),
			shadow2xl: Shadow.lerpStack(from.shadow2xl, to.shadow2xl, t),
			shadowInner: Shadow.lerpStack(from.shadowInner, to.shadowInner, t),
			shadowNone: []
		};
	}

	public static inline function defaults():ShadowTokens {
		return light();
	}
}
