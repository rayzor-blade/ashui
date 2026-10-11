package ashui.types;

/** How a replaced image fits its content box. Existing Brush.ImageFit values remain accepted. **/
enum abstract ObjectFit(Int) from Int to Int {
	var Cover = 0;
	var Contain = 1;
	var Fill = 2;
	/** Retained for images authored with the existing ImageFit.Tile API. **/
	var Tile = 3;
	/** The bitmap's intrinsic size, cropped to its box when needed. **/
	var None = 4;
	/** Contain without enlarging the bitmap beyond its intrinsic size. **/
	var ScaleDown = 5;

	@:from public static inline function fromImageFit(fit:Brush.ImageFit):ObjectFit
		return cast fit;
}
