package ashui.types;

import ashui.core.externs.BlincNative;

/** A length in a clip path: pixels, or a percentage of the element's box. **/
enum ClipLength {
	Px(value:Float);
	Percent(value:Float);
}

/**
	A shape an element and everything inside it are clipped to, as CSS's
	`clip-path`, in the element's own coordinates: it turns and scales with
	the element. Percentages are of the element's width for x and widths, of
	its height for y and heights, and for a circle's radius of its diagonal
	over √2, as in CSS. A radius left out reaches the closest side.

	```haxe
	node.set(Prop.ClipPath, ClipPath.circle());                    // the largest circle centred in the box
	node.set(Prop.ClipPath, ClipPath.inset(Px(8), Px(8), Px(8), Px(8), 12));
	```

	When clip paths are nested, the innermost one clips.
**/
class ClipPath implements IValue {
	public var ptr(default, null):hl.Abstract<"blinc_value">;

	function new(kind:Int, lengths:Array<Null<ClipLength>>, round:Float) {
		var values = new hl.Bytes(lengths.length * 4 + 4);
		var percent = 0, none = 0;
		for (i in 0...lengths.length)
			switch lengths[i] {
				case null:
					none |= 1 << i;
					values.setF32(i * 4, 0);
				case Px(v):
					values.setF32(i * 4, v);
				case Percent(v):
					percent |= 1 << i;
					values.setF32(i * 4, v);
			}
		ptr = BlincNative.blinc_clip_path(kind, values, percent, none, round);
	}

	/** `circle(radius at x y)`, centred in the box by default. **/
	public static function circle(?radius:ClipLength, ?x:ClipLength, ?y:ClipLength):ClipPath
		return new ClipPath(0, [radius, center(x), center(y)], -1);

	/** `ellipse(rx ry at x y)`, centred in the box by default. **/
	public static function ellipse(?rx:ClipLength, ?ry:ClipLength, ?x:ClipLength, ?y:ClipLength):ClipPath
		return new ClipPath(1, [rx, ry, center(x), center(y)], -1);

	/** `inset(top right bottom left round radius)`: the box shrunk by each side. **/
	public static function inset(top:ClipLength, right:ClipLength, bottom:ClipLength, left:ClipLength, round:Float = -1):ClipPath
		return new ClipPath(2, [top, right, bottom, left], round);

	/** `rect(top right bottom left round radius)`: edges measured from the box's top and left. **/
	public static function rect(top:ClipLength, right:ClipLength, bottom:ClipLength, left:ClipLength, round:Float = -1):ClipPath
		return new ClipPath(3, [top, right, bottom, left], round);

	/** `xywh(x y width height round radius)`. **/
	public static function xywh(x:ClipLength, y:ClipLength, width:ClipLength, height:ClipLength, round:Float = -1):ClipPath
		return new ClipPath(4, [x, y, width, height], round);

	static inline function center(v:Null<ClipLength>):ClipLength
		return v != null ? v : Percent(50);
}
