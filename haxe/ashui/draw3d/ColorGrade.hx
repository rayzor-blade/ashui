package ashui.draw3d;

/**
	A colour grade for a 3D scene's final image, as a film colourist would
	apply one. Dark parts of the image are tinted towards `shadows` and
	bright parts towards `highlights` (both `0xRRGGBB`; the tints change
	colour but not brightness). `saturation` scales how colourful the image
	is (1 keeps it), and `contrast` spreads tones apart around the middle
	grey (1 keeps it). `strength` blends between the original image (0)
	and the fully graded one (1).
**/
class ColorGrade {
	/** Cool shadows, warm highlights and a little extra contrast: a common look for night scenes. **/
	public static final NIGHT = new ColorGrade(0x8aa4d0, 0xfff0e2, 1.1, 0.92);

	public final shadows:Int;
	public final highlights:Int;
	public final contrast:Float;
	public final saturation:Float;
	public final strength:Float;

	public function new(shadows = 0xffffff, highlights = 0xffffff, contrast = 1.0, saturation = 1.0, strength = 1.0) {
		this.shadows = shadows;
		this.highlights = highlights;
		this.contrast = contrast;
		this.saturation = saturation;
		this.strength = strength;
	}

	/** A copy blended in by `strength`. **/
	public function at(strength:Float):ColorGrade
		return new ColorGrade(shadows, highlights, contrast, saturation, strength);
}
