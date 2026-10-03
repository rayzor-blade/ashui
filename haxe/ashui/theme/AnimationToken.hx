package ashui.theme;

/** A duration step of the theme's motion, fastest to slowest; see `AnimationTokens`. **/
enum abstract AnimationToken(Int) {
	var DurationFastest;
	var DurationFaster;
	var DurationFast;
	var DurationNormal;
	var DurationSlow;
	var DurationSlower;
	var DurationSlowest;
}
