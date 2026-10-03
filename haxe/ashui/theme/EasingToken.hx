package ashui.theme;

/** A timing curve of the theme's motion. **/
enum abstract EasingToken(Int) {
	var Default;
	var In;
	var Out;
	var InOut;
	/** Hover, press and other state changes. **/
	var State;
	/** Navigation and page transitions. **/
	var Nav;
	/** Popovers and badges, which overshoot a little. **/
	var Spring;
	/** Sheets and drawers. **/
	var Sheet;

	public function of(tokens:AnimationTokens):Easing {
		return switch (cast this : EasingToken) {
			case Default: tokens.easeDefault;
			case In: tokens.easeIn;
			case Out: tokens.easeOut;
			case InOut: tokens.easeInOut;
			case State: tokens.easeState;
			case Nav: tokens.easeNav;
			case Spring: tokens.easeSpring;
			case Sheet: tokens.easeSheet;
		}
	}
}
