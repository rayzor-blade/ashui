package ashui.svg;

import ashui.svg.PathData.PathCommand;
import ashui.svg.SvgDocument.FillRule;
import ashui.svg.SvgDocument.Paint;
import ashui.svg.SvgDocument.Parsed;
import ashui.svg.SvgDocument.SvgNode;
import ashui.svg.SvgDocument.SvgShape;

/**
	Reads an `<svg>` element, from Haxe's `Xml`, into shapes with their paint
	resolved. Runs at compile time for SVG in templates and at runtime for
	`SvgDocument.parse`, so both report the same errors: XML that is not an
	`<svg>`, and path data that does not parse. Everything else SVG allows is
	kept, whether or not this model describes it: an element it does not
	model (a gradient, text, `<use>`, a filter) is an `Other` node and a paint
	it cannot resolve (`url(#g)`, a colour name it does not know) an `Other`
	paint. The renderer draws the whole document, not this model.

	Paint properties (`fill`, `stroke`, their opacities, widths, caps and
	joins, and `color`) pass from a group to what is in it, as in SVG;
	`opacity` and `transform` belong to the element they are on. A property
	can be an attribute or a declaration in `style`, which wins.
**/
class SvgParser {
	/** Elements that only describe the image. **/
	static final IGNORED = ["title", "desc", "metadata"];

	/** The shapes this model reads into paths. **/
	static final SHAPES = ["path" => true, "rect" => true, "circle" => true, "ellipse" => true, "line" => true, "polyline" => true,
		"polygon" => true];

	public static function parse(xml:Xml):Parsed {
		var root = xml.nodeType == Document ? xml.firstElement() : xml;
		if (root == null || local(root.nodeName) != "svg")
			throw new SvgError("the root element is not <svg>");
		var width = length(root.get("width"));
		var height = length(root.get("height"));
		var box = root.get("viewBox") == null ? [] : numbers(root.get("viewBox"), "viewBox");
		// Without a usable viewBox, the size; without either, CSS's default 300 by 150.
		var viewBox:Array<Float> = box.length == 4 && box[2] > 0 && box[3] > 0 ? box : [
			0.0,
			0.0,
			width != null ? (width : Float) : 300.0,
			height != null ? (height : Float) : 150.0
		];
		var style = properties(root, Style.initial());
		return {
			viewBox: viewBox,
			width: width != null ? width : viewBox[2],
			height: height != null ? height : viewBox[3],
			nodes: children(root, style)
		};
	}

	static function children(parent:Xml, inherited:Style):Array<SvgNode> {
		var out = [];
		for (child in parent.elements()) {
			var node = element(child, inherited);
			if (node != null)
				out.push(node);
		}
		return out;
	}

	static function element(e:Xml, inherited:Style):Null<SvgNode> {
		var name = local(e.nodeName);
		if (IGNORED.indexOf(name) >= 0)
			return null;
		var style = properties(e, inherited);
		if (style.hidden)
			return null;
		var opacity = unit(own(e, "opacity"), "opacity");
		var transform = switch own(e, "transform") {
			case null: null;
			case t: Transforms.parse(t);
		}
		if (name == "g") {
			var kids = children(e, style);
			return kids.length == 0 ? null : Group(opacity, transform, kids);
		}
		if (!SHAPES.exists(name))
			return OtherElement(name, children(e, style));
		var path = switch name {
			case "path":
				var d = e.get("d");
				d == null ? [] : PathData.parse(d);
			case "rect": rect(e);
			case "circle":
				var r = num(e, "r");
				ellipse(num(e, "cx"), num(e, "cy"), r, r);
			case "ellipse": ellipse(num(e, "cx"), num(e, "cy"), num(e, "rx"), num(e, "ry"));
			case "line": [MoveTo(num(e, "x1"), num(e, "y1")), LineTo(num(e, "x2"), num(e, "y2"))];
			case "polyline": poly(e, false);
			case _: poly(e, true);
		}
		if (path.length == 0)
			return null;
		var shape:SvgShape = {
			path: path,
			fill: style.paint(style.fill),
			fillOpacity: style.fillOpacity,
			fillRule: style.fillRule,
			stroke: style.paint(style.stroke),
			strokeOpacity: style.strokeOpacity,
			strokeWidth: style.strokeWidth,
			lineCap: style.lineCap,
			lineJoin: style.lineJoin,
			miterLimit: style.miterLimit,
			opacity: opacity,
			transform: transform
		};
		return Shape(shape);
	}

	/** A rect, its corners rounded by `rx` and `ry`, either standing for both when one is missing. **/
	static function rect(e:Xml):Array<PathCommand> {
		var x = num(e, "x"), y = num(e, "y");
		var w = num(e, "width"), h = num(e, "height");
		if (w <= 0 || h <= 0)
			return [];
		var rx = length(e.get("rx"));
		var ry = length(e.get("ry"));
		if (rx == null)
			rx = ry != null ? ry : 0;
		if (ry == null)
			ry = rx;
		rx = Math.min(rx, w / 2);
		ry = Math.min(ry, h / 2);
		if (rx <= 0 || ry <= 0)
			return [MoveTo(x, y), LineTo(x + w, y), LineTo(x + w, y + h), LineTo(x, y + h), Close];
		return [
			MoveTo(x + rx, y),
			LineTo(x + w - rx, y),
			ArcTo(rx, ry, 0, false, true, x + w, y + ry),
			LineTo(x + w, y + h - ry),
			ArcTo(rx, ry, 0, false, true, x + w - rx, y + h),
			LineTo(x + rx, y + h),
			ArcTo(rx, ry, 0, false, true, x, y + h - ry),
			LineTo(x, y + ry),
			ArcTo(rx, ry, 0, false, true, x + rx, y),
			Close
		];
	}

	static function ellipse(cx:Float, cy:Float, rx:Float, ry:Float):Array<PathCommand> {
		if (rx <= 0 || ry <= 0)
			return [];
		return [
			MoveTo(cx - rx, cy),
			ArcTo(rx, ry, 0, true, false, cx + rx, cy),
			ArcTo(rx, ry, 0, true, false, cx - rx, cy),
			Close
		];
	}

	static function poly(e:Xml, closed:Bool):Array<PathCommand> {
		var points = numbers(e.get("points") == null ? "" : e.get("points"), "points");
		if (points.length < 4)
			return [];
		var out = [MoveTo(points[0], points[1])];
		var i = 2;
		while (i + 1 < points.length) {
			out.push(LineTo(points[i], points[i + 1]));
			i += 2;
		}
		if (closed)
			out.push(Close);
		return out;
	}

	/** `inherited` with what `e` sets itself. **/
	static function properties(e:Xml, inherited:Style):Style {
		var style = inherited.copy();
		for (name in Style.NAMES) {
			var v = own(e, name);
			if (v != null)
				style.set(name, v);
		}
		return style;
	}

	/** Property `name` of `e`: from its `style` attribute, or the attribute itself. **/
	static function own(e:Xml, name:String):Null<String> {
		var css = e.get("style");
		if (css != null)
			for (declaration in css.split(";")) {
				var colon = declaration.indexOf(":");
				if (colon > 0 && StringTools.trim(declaration.substr(0, colon)) == name)
					return StringTools.trim(declaration.substr(colon + 1));
			}
		var v = e.get(name);
		return v == null ? null : StringTools.trim(v);
	}

	/** A name without its namespace prefix: `svg:path` is `path`. **/
	static function local(name:String):String {
		var colon = name.indexOf(":");
		return colon < 0 ? name : name.substr(colon + 1);
	}

	static function num(e:Xml, name:String):Float {
		var v = length(e.get(name));
		return v == null ? 0 : v;
	}

	/**
		A length in user units: a number, optionally with a unit, `px` and the
		absolute ones converted; null when absent, a percentage, relative to
		the font, or not a length, which the renderer resolves on its own.
	**/
	public static function length(v:Null<String>):Null<Float> {
		if (v == null)
			return null;
		var m = ~/^\s*([-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?)\s*([a-zA-Z%]*)\s*$/;
		if (!m.match(v))
			return null;
		var f = Std.parseFloat(m.matched(1));
		return switch m.matched(2).toLowerCase() {
			case "" | "px": f;
			case "pt": f * 4 / 3;
			case "pc": f * 16;
			case "in": f * 96;
			case "cm": f * 96 / 2.54;
			case "mm": f * 96 / 25.4;
			case "q": f * 96 / 101.6;
			case _: null;
		}
	}

	/** A number from 0 to 1, or a percentage; 1 when absent or not a number. **/
	public static function unit(v:Null<String>, what:String):Float {
		if (v == null)
			return 1;
		var percent = StringTools.endsWith(v, "%");
		var f = Std.parseFloat(percent ? v.substr(0, v.length - 1) : v);
		if (Math.isNaN(f))
			return 1;
		if (percent)
			f /= 100;
		return Math.max(0, Math.min(1, f));
	}

	/** Numbers separated by whitespace or commas, up to the first thing that is neither, as SVG reads them. **/
	public static function numbers(v:String, what:String):Array<Float> {
		var out = [];
		var number = ~/[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?/;
		var rest = v;
		while (number.match(rest)) {
			if (!~/^[\s,]*$/.match(number.matchedLeft()))
				break;
			out.push(Std.parseFloat(number.matched(0)));
			rest = number.matchedRight();
		}
		return out;
	}
}

/** The paint properties in effect on an element, after what it inherits. **/
private class Style {
	public static final NAMES = [
		"fill", "fill-opacity", "fill-rule", "stroke", "stroke-opacity", "stroke-width", "stroke-linecap", "stroke-linejoin",
		"stroke-miterlimit", "color", "display", "visibility"
	];

	public var fill = "black";
	public var stroke = "none";
	public var fillOpacity = 1.0;
	public var strokeOpacity = 1.0;
	public var strokeWidth = 1.0;
	public var fillRule:FillRule = NonZero;
	public var lineCap = "butt";
	public var lineJoin = "miter";
	public var miterLimit = 4.0;
	/** What `currentColor` is: the element's own colour unless an SVG `color` sets one. **/
	public var color:Null<String> = null;
	public var hidden = false;

	public function new() {}

	public static function initial():Style
		return new Style();

	public function copy():Style {
		var s = new Style();
		s.fill = fill;
		s.stroke = stroke;
		s.fillOpacity = fillOpacity;
		s.strokeOpacity = strokeOpacity;
		s.strokeWidth = strokeWidth;
		s.fillRule = fillRule;
		s.lineCap = lineCap;
		s.lineJoin = lineJoin;
		s.miterLimit = miterLimit;
		s.color = color;
		// `display: none` hides the element and what is in it; it is not passed down otherwise.
		return s;
	}

	public function set(name:String, v:String):Void {
		if (v == "inherit")
			return;
		switch name {
			case "fill":
				fill = v;
			case "stroke":
				stroke = v;
			case "fill-opacity":
				fillOpacity = SvgParser.unit(v, name);
			case "stroke-opacity":
				strokeOpacity = SvgParser.unit(v, name);
			case "stroke-width":
				var w = SvgParser.length(v);
				strokeWidth = w == null ? 1 : Math.max(0, w);
			// Values this model does not know leave the property as it was; the renderer reads them itself.
			case "fill-rule":
				if (v == "nonzero")
					fillRule = NonZero;
				else if (v == "evenodd")
					fillRule = EvenOdd;
			case "stroke-linecap":
				if (["butt", "round", "square"].indexOf(v) >= 0)
					lineCap = v;
			case "stroke-linejoin":
				if (["miter", "round", "bevel", "miter-clip", "arcs"].indexOf(v) >= 0)
					lineJoin = v;
			case "stroke-miterlimit":
				var n = SvgParser.numbers(v, name);
				if (n.length > 0)
					miterLimit = Math.max(1, n[0]);
			case "color":
				if (v.toLowerCase() != "currentcolor")
					color = v;
			case "display":
				if (v == "none")
					hidden = true;
			case "visibility":
				hidden = v == "hidden" || v == "collapse";
		}
	}

	/**
		Paint `v`, with `currentColor` resolved when an SVG `color` set it. A
		gradient, a pattern or a colour this model cannot read is `Other`.
	**/
	public function paint(v:String):Paint {
		var t = StringTools.trim(v);
		if (t == "none" || t == "transparent")
			return NoPaint;
		if (t.toLowerCase() == "currentcolor")
			return color == null ? CurrentColor : paint(color);
		var c = Colors.tryParse(t);
		return c == null ? Other(t) : Solid(c.rgb, c.alpha);
	}
}
