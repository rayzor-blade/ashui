package ashui.theme;

typedef AnimationTokensData = {
	/** Durations in milliseconds. **/
	final durationFastest:Int;
	final durationFaster:Int;
	final durationFast:Int;
	final durationNormal:Int;
	final durationSlow:Int;
	final durationSlower:Int;
	final durationSlowest:Int;

	final easeDefault:Easing;
	final easeIn:Easing;
	final easeOut:Easing;
	final easeInOut:Easing;
	/** Hover, press and other state changes. **/
	final easeState:Easing;
	/** Navigation and page transitions. **/
	final easeNav:Easing;
	/** Popovers and badges, which overshoot a little. **/
	final easeSpring:Easing;
	/** Sheets and drawers. **/
	final easeSheet:Easing;
}

/** The theme's motion: durations and curves. **/
@:forward
abstract AnimationTokens(AnimationTokensData) from AnimationTokensData to AnimationTokensData {
	/** `token`'s duration in milliseconds. **/
	public function get(token:AnimationToken):Int {
		return switch token {
			case DurationFastest: this.durationFastest;
			case DurationFaster: this.durationFaster;
			case DurationFast: this.durationFast;
			case DurationNormal: this.durationNormal;
			case DurationSlow: this.durationSlow;
			case DurationSlower: this.durationSlower;
			case DurationSlowest: this.durationSlowest;
		}
	}

	/** `token`'s duration in seconds. **/
	public inline function getSeconds(token:AnimationToken):Float {
		return get(token) / 1000;
	}

	/** Animation durations, easing out by default. **/
	public static function defaults():AnimationTokens {
		return {
			durationFastest: 75,
			durationFaster: 100,
			durationFast: 150,
			durationNormal: 200,
			durationSlow: 300,
			durationSlower: 400,
			durationSlowest: 500,
			easeDefault: EaseOut,
			easeIn: EaseIn,
			easeOut: EaseOut,
			easeInOut: EaseInOut,
			easeState: EaseOut,
			easeNav: EaseInOut,
			easeSpring: EaseOut,
			easeSheet: EaseOut
		};
	}
}
