package ashui.types;

/** A clip path as CSS describes it, read but not yet made: what `ClipPathCss.parse` gives. **/
enum ClipShape {
	NoClip;
	Circle(radius:Null<ClipLength>, x:ClipLength, y:ClipLength);
	Ellipse(rx:Null<ClipLength>, ry:Null<ClipLength>, x:ClipLength, y:ClipLength);
	Inset(top:ClipLength, right:ClipLength, bottom:ClipLength, left:ClipLength, round:Float);
	Rect(top:ClipLength, right:ClipLength, bottom:ClipLength, left:ClipLength, round:Float);
	Xywh(x:ClipLength, y:ClipLength, width:ClipLength, height:ClipLength, round:Float);
	Polygon(points:Array<{x:ClipLength, y:ClipLength}>);
	Path(d:String);
}

/**
	Reads CSS's `clip-path` value: `none`, `circle(40% at left top)`,
	`ellipse(50% 30%)`, `inset(8px 12px round 16px)`, `rect(…)`, `xywh(…)`,
	`polygon(50% 0, 100% 100%, 0 100%)` and `path("M0 0 …")`. Lengths are
	pixels (`px`, or a bare 0) or percentages; a radius is left out, or
	`closest-side`, to reach the closest side. Plain Haxe, so the `tw` macro
	reads `[clip-path:…]` classes with it at compile time, and
	`ClipPath.parse` reads strings at run time.
**/
class ClipPathCss {
	/** `css` read; throws a `String` saying what is wrong. **/
	public static function parse(css:String):ClipShape {
		var s = StringTools.trim(css);
		if (s == "none")
			return NoClip;
		var call = ~/^([a-z]+)\s*\(([\s\S]*)\)$/;
		if (!call.match(s))
			throw 'clip-path "$css" is not none or a shape function';
		var name = call.matched(1), body = StringTools.trim(call.matched(2));
		return switch name {
			case "circle":
				var parts = atSplit(body);
				var words = words(parts.size);
				if (words.length > 1)
					throw 'circle() takes one radius, not "${parts.size}"';
				var pos = position(parts.at);
				Circle(words.length == 0 ? null : radius(words[0]), pos.x, pos.y);
			case "ellipse":
				var parts = atSplit(body);
				var words = words(parts.size);
				if (words.length != 0 && words.length != 2)
					throw 'ellipse() takes two radii or none, not "${parts.size}"';
				var pos = position(parts.at);
				Ellipse(words.length == 0 ? null : radius(words[0]), words.length == 0 ? null : radius(words[1]), pos.x, pos.y);
			case "inset":
				var r = rounded(body);
				var v = [for (w in words(r.rest)) length(w)];
				switch v.length {
					case 1: Inset(v[0], v[0], v[0], v[0], r.round);
					case 2: Inset(v[0], v[1], v[0], v[1], r.round);
					case 3: Inset(v[0], v[1], v[2], v[1], r.round);
					case 4: Inset(v[0], v[1], v[2], v[3], r.round);
					case _: throw 'inset() takes one to four lengths, not "${r.rest}"';
				}
			case "rect" | "xywh":
				var r = rounded(body);
				var v = [for (w in words(r.rest)) length(w)];
				if (v.length != 4)
					throw '$name() takes four lengths, not "${r.rest}"';
				name == "rect" ? Rect(v[0], v[1], v[2], v[3], r.round) : Xywh(v[0], v[1], v[2], v[3], r.round);
			case "polygon":
				var items = [for (p in body.split(",")) StringTools.trim(p)];
				fillRule(items);
				Polygon([
					for (p in items) {
						var xy = words(p);
						if (xy.length != 2)
							throw 'a polygon point is two lengths, not "$p"';
						{x: length(xy[0]), y: length(xy[1])};
					}
				]);
			case "path":
				var items = body.split(",");
				if (items.length > 1) {
					var rule = [StringTools.trim(items[0])];
					fillRule(rule);
					if (rule.length != 0)
						throw 'path() takes a fill rule and a string, not "$body"';
					body = StringTools.trim(items.slice(1).join(","));
				}
				var quoted = ~/^(["'])([\s\S]*)\1$/;
				if (!quoted.match(body))
					throw 'path() takes its path data as a quoted string, not "$body"';
				Path(quoted.matched(2));
			case other:
				throw 'clip-path "$other()" is not circle, ellipse, inset, rect, xywh, polygon or path';
		}
	}

	/** Takes a leading fill rule off `items`: nonzero, CSS's default, is the one there is yet. **/
	static function fillRule(items:Array<String>):Void {
		if (items.length == 0)
			return;
		switch items[0] {
			case "nonzero":
				items.shift();
			case "evenodd":
				throw "the evenodd fill rule is not supported yet; clip paths fill by nonzero";
			case _:
		}
	}

	static function atSplit(body:String):{size:String, at:String} {
		var i = (" " + body + " ").indexOf(" at ");
		return i < 0 ? {size: body, at: ""} : {size: StringTools.trim(body.substr(0, i)), at: StringTools.trim(body.substr(i + 3))};
	}

	static function rounded(body:String):{rest:String, round:Float} {
		var i = (" " + body + " ").indexOf(" round ");
		if (i < 0)
			return {rest: body, round: -1};
		var r = StringTools.trim(body.substr(i + 6));
		return switch length(r) {
			case Px(v): {rest: StringTools.trim(body.substr(0, i)), round: v};
			case _: throw 'round takes a length in pixels, not "$r"';
		}
	}

	static function words(s:String):Array<String>
		return [for (w in ~/\s+/g.split(StringTools.trim(s))) if (w != "") w];

	static function radius(w:String):Null<ClipLength> {
		return switch w {
			case "closest-side": null;
			case "farthest-side": throw "farthest-side is not supported yet; give the radius or closest-side";
			case _: length(w);
		}
	}

	/** After `at`: one or two positions, keywords or lengths; the centre when left out. **/
	static function position(s:String):{x:ClipLength, y:ClipLength} {
		var w = words(s);
		function keyword(k:String, vertical:Bool):Null<ClipLength> {
			return switch k {
				case "center": Percent(50);
				case "left" if (!vertical): Percent(0);
				case "right" if (!vertical): Percent(100);
				case "top" if (vertical): Percent(0);
				case "bottom" if (vertical): Percent(100);
				case _: null;
			}
		}
		function one(k:String, vertical:Bool):ClipLength {
			var kw = keyword(k, vertical);
			return kw != null ? kw : length(k);
		}
		return switch w.length {
			case 0: {x: Percent(50), y: Percent(50)};
			case 1:
				// One word: a vertical keyword sets y, anything else x.
				w[0] == "top" || w[0] == "bottom" ? {x: Percent(50), y: one(w[0], true)} : {x: one(w[0], false), y: Percent(50)};
			case 2:
				// Keywords may come in either order: `top left` is `left top`.
				w[0] == "top" || w[0] == "bottom" || w[1] == "left" || w[1] == "right" ? {x: one(w[1], false), y: one(w[0], true)} : {
					x: one(w[0], false),
					y: one(w[1], true)
				};
			case _: throw 'a position is one or two values, not "$s"';
		}
	}

	static function length(w:String):ClipLength {
		var n = ~/^(-?(?:\d+\.?\d*|\.\d+))(px|%)?$/;
		if (!n.match(w))
			throw '"$w" is not a length in px or %';
		var v = Std.parseFloat(n.matched(1));
		return switch n.matched(2) {
			case "%": Percent(v);
			case "px": Px(v);
			case _ if (v == 0): Px(0);
			case _: throw '"$w" needs a unit, px or %';
		}
	}
}
