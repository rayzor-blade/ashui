package ashui.svg;

import ashui.svg.PathData.n;
import ashui.svg.SvgDocument.Paint;
import ashui.svg.SvgDocument.Parsed;
import ashui.svg.SvgDocument.SvgNode;

/**
	Writes parsed SVG back as markup with every property spelled out and every
	path absolute, so equal images have equal markup and the rasterizer reads
	nothing ashui did not check.
**/
class SvgWriter {
	public static function write(p:Parsed):String {
		var out = new StringBuf();
		out.add('<svg xmlns="http://www.w3.org/2000/svg" viewBox="${p.viewBox.map(n).join(" ")}" width="${n(p.width)}" height="${n(p.height)}">');
		for (node in p.nodes)
			writeNode(node, out);
		out.add("</svg>");
		return out.toString();
	}

	/** True when `currentColor` is the only colour, so the image is a coverage mask tinted when drawn. **/
	public static function isMask(nodes:Array<SvgNode>):Bool {
		for (node in nodes)
			switch node {
				case Group(_, _, kids):
					if (!isMask(kids))
						return false;
				case Shape(s):
					if (s.fill.match(Solid(_, _)) || s.stroke.match(Solid(_, _)))
						return false;
			}
		return true;
	}

	static function writeNode(node:SvgNode, out:StringBuf):Void {
		switch node {
			case Group(opacity, transform, kids):
				out.add("<g");
				common(opacity, transform, out);
				out.add(">");
				for (kid in kids)
					writeNode(kid, out);
				out.add("</g>");
			case Shape(s):
				out.add('<path d="${PathData.write(s.path)}"');
				paint("fill", s.fill, s.fillOpacity, out);
				if (s.fillRule == EvenOdd)
					out.add(' fill-rule="evenodd"');
				paint("stroke", s.stroke, s.strokeOpacity, out);
				if (s.stroke != NoPaint) {
					out.add(' stroke-width="${n(s.strokeWidth)}" stroke-linecap="${s.lineCap}" stroke-linejoin="${s.lineJoin}"');
					if (s.lineJoin == "miter")
						out.add(' stroke-miterlimit="${n(s.miterLimit)}"');
				}
				common(s.opacity, s.transform, out);
				out.add("/>");
		}
	}

	static function common(opacity:Float, transform:Null<Array<Float>>, out:StringBuf):Void {
		if (opacity < 1)
			out.add(' opacity="${n(opacity)}"');
		if (transform != null)
			out.add(' transform="matrix(${transform.map(n).join(" ")})"');
	}

	static function paint(name:String, p:Paint, opacity:Float, out:StringBuf):Void {
		switch p {
			case NoPaint:
				out.add(' $name="none"');
			case CurrentColor:
				out.add(' $name="currentColor"');
				if (opacity < 1)
					out.add(' $name-opacity="${n(opacity)}"');
			case Solid(rgb, alpha):
				out.add(' $name="#${StringTools.hex(rgb, 6)}"');
				if (opacity * alpha < 1)
					out.add(' $name-opacity="${n(opacity * alpha)}"');
		}
	}
}
