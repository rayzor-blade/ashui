package ashui.draw;

/**
	How a canvas draw combines with what is under it. Each mode is the GPU's own blend of the draw's premultiplied colour
	with the target, so none reads the target in a shader: `Overlay`, `HardLight`, `Difference` and the like are not here.
	Over transparent pixels `Multiply` leaves them transparent, where Flash shows the draw as `Normal`.
**/
enum abstract BlendMode(Int) to Int {
	/** The draw over what is under it. **/
	var Normal = 0;

	/** The draw's colour added to what is under it, clamped at white. **/
	var Add = 1;

	/** The draw's colour taken from what is under it, clamped at black. **/
	var Subtract = 2;

	/** What is under it times the draw's colour. **/
	var Multiply = 3;

	/** The inverse of the product of the inverses: lightens, never darkens. **/
	var Screen = 4;

	/** How many modes there are. **/
	public static inline var COUNT = 5;
}
