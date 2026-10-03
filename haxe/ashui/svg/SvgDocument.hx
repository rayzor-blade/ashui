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

/** A shape, or a group drawn as one layer under its own opacity and transform. **/
enum SvgNode {
	Shape(shape:SvgShape);
	Group(opacity:Float, transform:Null<Array<Float>>, children:Array<SvgNode>);
}

/**
	A parsed SVG image: its coordinate box (`viewBox`), its natural size, and
	its shapes. ashui reads SVG itself, with Haxe's XML support, and keeps
	shapes, paths, solid paints, groups and transforms; gradients, text,
	`<use>` and masks are not supported yet and are reported as errors.

	Get one at compile time with `SvgDocument.embed("icon.svg")`, from Haxe
	inline markup with `SvgDocument.of(<svg viewBox="0 0 24 24">...</svg>)`,
	or by writing the `<svg>` straight into an hxx template; malformed SVG
	is then a compile error. At runtime `SvgDocument.parse(source)` reads a
	string. Documents with the same content are one document, so an icon used
	many times is rasterized once per size.

	An SVG whose only colour is `currentColor` is a **mask**: it is drawn in
	the colour of the element showing it, which can follow the theme or
	animate without rasterizing it again.
**/
class SvgDocument {
	static var nextId = 0;
	static final byMarkup = new Map<String, SvgDocument>();
	static final byId = new Map<Int, SvgDocument>();

	/** Names the document to the renderer. **/
	public final id:Int;

	/** The SVG as ashui writes it back, every path absolute: what is rasterized. **/
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

	/** The document `parse` gave a slot of, if any. **/
	public static function get(id:Int):Null<SvgDocument>
		return byId.get(id);

	/** `source`, an SVG document; throws `SvgError` when it is malformed or unsupported. **/
	public static function parse(source:String):SvgDocument {
		var xml = try Xml.parse(source) catch (e:haxe.Exception) throw new SvgError('not XML: ${e.message}');
		return fromParsed(SvgParser.parse(xml));
	}

	/** The document of an already parsed `<svg>` element. **/
	public static function fromXml(xml:Xml):SvgDocument
		return fromParsed(SvgParser.parse(xml));

	static function fromParsed(parsed:Parsed):SvgDocument {
		var markup = SvgWriter.write(parsed);
		var known = byMarkup.get(markup);
		if (known != null)
			return known;
		return register(new SvgDocument(markup, SvgWriter.isMask(parsed.nodes), parsed.width, parsed.height, parsed.nodes));
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
		var markup = SvgWriter.write(parsed);
		var mask = SvgWriter.isMask(parsed.nodes);
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
