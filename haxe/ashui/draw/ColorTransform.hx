package ashui.draw;

/**
	A change of a drawn colour: each of red, green, blue and alpha, from 0 to 1, is multiplied by its multiplier and then has
	its offset added, as Flash's `ColorTransform` does with offsets divided by 255. Immutable.
**/
class ColorTransform {
	public static final IDENTITY = new ColorTransform();

	public final redMultiplier:Float;
	public final greenMultiplier:Float;
	public final blueMultiplier:Float;
	public final alphaMultiplier:Float;
	public final redOffset:Float;
	public final greenOffset:Float;
	public final blueOffset:Float;
	public final alphaOffset:Float;

	public function new(redMultiplier = 1.0, greenMultiplier = 1.0, blueMultiplier = 1.0, alphaMultiplier = 1.0, redOffset = 0.0, greenOffset = 0.0,
			blueOffset = 0.0, alphaOffset = 0.0) {
		this.redMultiplier = redMultiplier;
		this.greenMultiplier = greenMultiplier;
		this.blueMultiplier = blueMultiplier;
		this.alphaMultiplier = alphaMultiplier;
		this.redOffset = redOffset;
		this.greenOffset = greenOffset;
		this.blueOffset = blueOffset;
		this.alphaOffset = alphaOffset;
	}

	/** Whether it leaves every colour as it is. **/
	public function isIdentity():Bool
		return redMultiplier == 1 && greenMultiplier == 1 && blueMultiplier == 1 && alphaMultiplier == 1 && redOffset == 0 && greenOffset == 0
			&& blueOffset == 0 && alphaOffset == 0;

	/** This transform applied to what `inner` has already changed: a colour goes through `inner` first. **/
	public function after(inner:ColorTransform):ColorTransform
		return new ColorTransform(redMultiplier * inner.redMultiplier, greenMultiplier * inner.greenMultiplier, blueMultiplier * inner.blueMultiplier,
			alphaMultiplier * inner.alphaMultiplier, redMultiplier * inner.redOffset + redOffset, greenMultiplier * inner.greenOffset + greenOffset,
			blueMultiplier * inner.blueOffset + blueOffset, alphaMultiplier * inner.alphaOffset + alphaOffset);
}
