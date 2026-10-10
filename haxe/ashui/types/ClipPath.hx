package ashui.types;

import ashui.core.externs.BlincNative;
import ashui.types.ClipLength;
import ashui.types.ClipPathCss;

/**
	A shape an element and everything inside it are clipped to, as CSS's
	`clip-path`, in the element's own coordinates: it turns and scales with
	the element. Percentages are of the element's width for x and widths, of
	its height for y and heights, and for a circle's radius of its diagonal
	over √2, as in CSS. A radius left out reaches the closest side.

	```haxe
	node.set(Prop.ClipPath, ClipPath.circle());                    // the largest circle centred in the box
	node.set(Prop.ClipPath, ClipPath.inset(Px(8), Px(8), Px(8), Px(8), 12));
	node.set(Prop.ClipPath, ClipPath.polygon([{x: Percent(50), y: Px(0)}, {x: Percent(100), y: Percent(100)}, {x: Px(0), y: Percent(100)}]));
	```

	In a class string, Tailwind's arbitrary property:
	`[clip-path:circle(40%_at_left_top)]`, underscores for spaces, read and
	checked at compile time; `ClipPath.parse` reads CSS at run time.

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

	/** `polygon(x1 y1, x2 y2, …)`: the points in order, joined back to the first; inside by the nonzero rule, CSS's default. **/
	public static function polygon(points:Array<{x:ClipLength, y:ClipLength}>):ClipPath {
		var values = new hl.Bytes(points.length * 8 + 8);
		var percent = new hl.Bytes(points.length * 2 + 2);
		for (i in 0...points.length)
			for (axis in 0...2) {
				var l = axis == 0 ? points[i].x : points[i].y;
				var k = i * 2 + axis;
				switch l {
					case Px(v):
						values.setF32(k * 4, v);
						percent.setUI8(k, 0);
					case Percent(v):
						values.setF32(k * 4, v);
						percent.setUI8(k, 1);
				}
			}
		return fromPolygon(BlincNative.blinc_clip_polygon(values, percent, points.length, false));
	}

	/**
		`path("M 0 0 L …")`: SVG path data in the element's pixels, curves
		and arcs cut into short straight steps; each subpath closes. Inside is
		by the nonzero rule, CSS's default: a hole is a subpath that runs the
		other way round from the one around it. `evenOdd()` fills it by the
		even-odd rule instead.
	**/
	public static function path(d:String):ClipPath {
		var rings = ashui.svg.PathData.flatten(ashui.svg.PathData.parse(d));
		var flat:Array<Float> = [];
		for (ring in rings) {
			if (flat.length > 0) {
				flat.push(BREAK);
				flat.push(BREAK);
			}
			for (v in ring)
				flat.push(v);
		}
		var values = new hl.Bytes(flat.length * 4 + 4);
		for (i in 0...flat.length)
			values.setF32(i * 4, flat[i]);
		return fromPolygon(BlincNative.blinc_clip_polygon(values, null, Std.int(flat.length / 2), true));
	}

	/**
		This polygon or path filled by the even-odd rule: a point is inside
		when a ray from it crosses the outline an odd number of times, so a
		ring inside another is a hole whichever way it runs. A new clip path;
		another shape is returned as it is.
	**/
	public function evenOdd():ClipPath {
		var marked = BlincNative.blinc_clip_even_odd(ptr);
		return marked == null ? this : fromPolygon(marked);
	}

	/** Between two rings of a path's points, a point at this x and y. **/
	@:noCompletion public static inline var BREAK = 1e30;

	static function fromPolygon(ptr:hl.Abstract<"blinc_value">):ClipPath {
		var made:ClipPath = Type.createEmptyInstance(ClipPath);
		made.ptr = ptr;
		return made;
	}

	/** No clip: what `none` is, for a state variant that takes a clip away. **/
	public static function none():ClipPath
		return new ClipPath(-1, [], -1);

	/** CSS's `clip-path` value, as `ClipPathCss.parse` reads it; throws a `String` when it is not one. **/
	public static function parse(css:String):ClipPath
		return of(ClipPathCss.parse(css));

	/** The clip path `shape` describes. **/
	public static function of(shape:ClipShape):ClipPath {
		return switch shape {
			case NoClip: none();
			case Circle(r, x, y): circle(r, x, y);
			case Ellipse(rx, ry, x, y): ellipse(rx, ry, x, y);
			case Inset(t, r, b, l, round): inset(t, r, b, l, round);
			case Rect(t, r, b, l, round): rect(t, r, b, l, round);
			case Xywh(x, y, w, h, round): xywh(x, y, w, h, round);
			case Polygon(points): polygon(points);
			case Path(d): path(d);
			case EvenOdd(inner): of(inner).evenOdd();
		}
	}

	static inline function center(v:Null<ClipLength>):ClipLength
		return v != null ? v : Percent(50);
}
