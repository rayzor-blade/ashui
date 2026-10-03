package ashui.types;

/** A length in a clip path: pixels, or a percentage of the element's box. **/
enum ClipLength {
	Px(value:Float);
	Percent(value:Float);
}
