package ashui.theme;

/** A value of the theme's corner smoothing; see `ShapeTokens`. **/
enum abstract ShapeToken(Int) {
	var CornerSmoothing;
	var CornerExponent;
	var SmoothingThreshold;
}
