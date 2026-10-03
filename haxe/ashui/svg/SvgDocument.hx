package ashui.svg;

import ashui.svg.PathData.PathCommand;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
#end

/** What fills or strokes a shape. **/
enum Paint {
	NoPaint;
	/** The element's colour, which a theme or class sets; one SVG can then be drawn in any colour. **/
	CurrentColor;
	/** A fixed colour, `0xRRGGBB`, and its alpha from 0 to 1. **/
	Solid(rgb:Int, alpha:Float);
	/** A paint this model does not read, such as a gradient `url(#g)`; the renderer draws it. **/
	Other(value:String);
}

/** Which parts of a self-crossing outline count as inside. **/
enum FillRule {
	NonZero;
	EvenOdd;
}

/** A shape with its paint resolved: what it inherited from its groups is already applied. **/
typedef SvgShape = {
	final path:Array<PathCommand>;
	final fill:Paint;
	final fillOpacity:Float;
	final fillRule:FillRule;
	final stroke:Paint;
	final strokeOpacity:Float;
	final strokeWidth:Float;
	/** `butt`, `round` or `square`. **/
	final lineCap:String;
	/** `miter`, `round` or `bevel`. **/
	final lineJoin:String;
	final miterLimit:Float;
	final opacity:Float;
	/** `[a, b, c, d, e, f]`: `(x, y)` maps to `(a·x + c·y + e, b·x + d·y + f)`. **/
	final transform:Null<Array<Float>>;
}

/** A shape, or a group drawn as one layer under its own opacity and transform, or an element this model does not describe. **/
enum SvgNode {
	Shape(shape:SvgShape);
	Group(opacity:Float, transform:Null<Array<Float>>, children:Array<SvgNode>);
	/** A gradient, text, `<use>`, a filter or any element besides shapes and groups, with what is inside it. **/
	OtherElement(name:String, children:Array<SvgNode>);
}

/**
	An SVG image: its markup, its natural size, and its shapes. Any SVG is
	drawn whole: gradients, patterns, text, `<use>`, clip paths, masks,
	filters, images and CSS in `<style>` included. ashui also reads it, with
	Haxe's XML support, into a typed model of its shapes, paths, paints,
	groups and transforms, in `nodes`; elements outside that model are
	`Other` nodes there and still drawn.

	Get one at compile time with `SvgDocument.embed("icon.svg")`, from Haxe
	inline markup with `SvgDocument.of(<svg viewBox="0 0 24 24">...</svg>)`,
	or by writing the `<svg>` straight into an hxx template; malformed SVG
	is then a compile error, as is path data that does not parse. At runtime `SvgDocument.parse(source)` reads a
	string. Documents with the same content are one document, so an icon used
	many times is rasterized once per size.

	`currentColor` in an SVG is the colour of the element showing it. An SVG
	whose only colour is `currentColor`, in shapes and groups alone, is a
	**mask**: rasterized once and tinted when drawn, so it can follow the
	theme or animate without rasterizing it again. Any other SVG is
	rasterized with that colour in it.
**/
class SvgDocument {
	static var nextId = 0;
	static final byMarkup = new Map<String, SvgDocument>();
	static final byId = new Map<Int, SvgDocument>();

	/** Names the document to the renderer. **/
	public final id:Int;

	/** The SVG as written, read as XML and written back so it is well-formed: what is rasterized. **/
	public final markup:String;

	/** True when its only colour is `currentColor`. **/
	public final mask:Bool;

	/** Its natural size: its `width` and `height`, or its viewBox's. **/
	public final width:Float;

	public final height:Float;

	/** The shapes, read again from `markup` on first use when compiled in. **/
	public var nodes(get, null):Array<SvgNode>;

	function new(markup:String, mask:Bool, width:Float, height:Float, ?nodes:Array<SvgNode>) {
		this.id = nextId++;
		this.markup = markup;
		this.mask = mask;
		this.width = width;
		this.height = height;
		this.nodes = nodes;
	}

	function get_nodes():Array<SvgNode> {
		if (nodes == null)
			nodes = SvgParser.parse(Xml.parse(markup)).nodes;
		return nodes;
	}

	/** `markup` with `currentColor` as `color`, a CSS colour, unless its `<svg>` sets a colour of its own. **/
	public function withColor(color:String):String {
		var tagEnd = markup.indexOf(">");
		if (~/\scolor\s*=/.match(markup.substring(0, tagEnd)))
			return markup;
		var nameEnd = 1;
		while (nameEnd < tagEnd && !StringTools.isSpace(markup, nameEnd) && markup.charAt(nameEnd) != "/")
			nameEnd++;
		return markup.substr(0, nameEnd) + ' color="$color"' + markup.substr(nameEnd);
	}

	/** The document `parse` gave a slot of, if any. **/
	public static function get(id:Int):Null<SvgDocument>
		return byId.get(id);

	/** `source`, an SVG document; throws `SvgError` when it is malformed. **/
	public static function parse(source:String):SvgDocument {
		var xml = try Xml.parse(source) catch (e:haxe.Exception) throw new SvgError('not XML: ${e.message}');
		return fromXml(xml);
	}

	/** The document of an already parsed `<svg>` element. **/
	public static function fromXml(xml:Xml):SvgDocument {
		var parsed = SvgParser.parse(xml);
		var markup = write(xml);
		var known = byMarkup.get(markup);
		if (known != null)
			return known;
		return register(new SvgDocument(markup, isMask(parsed.nodes), parsed.width, parsed.height, parsed.nodes));
	}

	/**
		The `<svg>` element of `xml` as markup, with its SVG namespace
		declared, and XLink's when it uses it, as a renderer needs. Attributes
		are written sorted and comments left out, so the same SVG is the same
		markup whichever way it was read.
	**/
	public static function write(xml:Xml):String {
		var root = xml.nodeType == Document ? xml.firstElement() : xml;
		var out = new StringBuf();
		writeNode(root, out);
		var markup = out.toString();
		var namespaces = "";
		if (root.nodeName == "svg" && !root.exists("xmlns"))
			namespaces += ' xmlns="http://www.w3.org/2000/svg"';
		if (!root.exists("xmlns:xlink") && markup.indexOf("xlink:") >= 0)
			namespaces += ' xmlns:xlink="http://www.w3.org/1999/xlink"';
		var nameEnd = root.nodeName.length + 1;
		return markup.substr(0, nameEnd) + namespaces + markup.substr(nameEnd);
	}

	static function writeNode(x:Xml, out:StringBuf):Void {
		switch x.nodeType {
			case Element:
				out.add("<" + x.nodeName);
				var names = [for (a in x.attributes()) a];
				names.sort(Reflect.compare);
				for (a in names)
					out.add(' $a="${StringTools.htmlEscape(x.get(a), true)}"');
				if (!x.iterator().hasNext()) {
					out.add("/>");
					return;
				}
				out.add(">");
				for (child in x)
					writeNode(child, out);
				out.add("</" + x.nodeName + ">");
			case PCData:
				out.add(StringTools.htmlEscape(x.nodeValue));
			case CData:
				out.add("<![CDATA[" + x.nodeValue + "]]>");
			case _:
		}
	}

	/**
		True when `currentColor` is the only paint, in shapes and groups alone,
		so the image is coverage tinted when drawn. Any element outside the
		model may paint on its own, so it is not a mask.
	**/
	public static function isMask(nodes:Array<SvgNode>):Bool {
		for (node in nodes)
			switch node {
				case Group(_, _, kids):
					if (!isMask(kids))
						return false;
				case Shape(s):
					if (!s.fill.match(NoPaint | CurrentColor) || !s.stroke.match(NoPaint | CurrentColor))
						return false;
				case OtherElement(_, _):
					return false;
			}
		return true;
	}

	/** A document the compiler parsed and checked; what `embed`, `of` and hxx emit. **/
	@:noCompletion
	public static function compiled(markup:String, mask:Bool, width:Float, height:Float):SvgDocument {
		var known = byMarkup.get(markup);
		if (known != null)
			return known;
		return register(new SvgDocument(markup, mask, width, height));
	}

	static function register(doc:SvgDocument):SvgDocument {
		byMarkup.set(doc.markup, doc);
		byId.set(doc.id, doc);
		return doc;
	}

	/** The SVG file at `path`, relative to the working directory of the build, read and checked at compile time. **/
	public static macro function embed(path:String):Expr {
		var pos = Context.currentPos();
		var source = try sys.io.File.getContent(path) catch (e:Dynamic) Context.error('svg: cannot read $path', pos);
		return compileSource(source, pos);
	}

	/** An SVG written as Haxe inline markup, `of(<svg ...>...</svg>)`, read and checked at compile time. **/
	public static macro function of(markup:Expr):Expr {
		var source = switch markup.expr {
			case EMeta({name: ":markup"}, {expr: EConst(CString(s))}): s;
			case EConst(CString(s)): s;
			case _: Context.error("svg: expected inline <svg> markup or a string literal", markup.pos);
		}
		return compileSource(source, markup.pos);
	}

	#if macro
	static function compileSource(source:String, pos:Position):Expr {
		var xml = try Xml.parse(source) catch (e:haxe.Exception) Context.error('svg: not XML: ${e.message}', pos);
		return compileXml(xml, pos);
	}

	/** The expression of a document parsed from `xml` now, or a compile error at `pos`. **/
	public static function compileXml(xml:Xml, pos:Position):Expr {
		var parsed = try SvgParser.parse(xml) catch (e:SvgError) Context.error('svg: ${e.message}', pos);
		var markup = write(xml);
		var mask = isMask(parsed.nodes);
		return macro @:pos(pos) ashui.svg.SvgDocument.compiled($v{markup}, $v{mask}, $v{parsed.width}, $v{parsed.height});
	}
	#end
}

/** What the parser reads from an `<svg>` element. **/
typedef Parsed = {
	final viewBox:Array<Float>;
	final width:Float;
	final height:Float;
	final nodes:Array<SvgNode>;
}
