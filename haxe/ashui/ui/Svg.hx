package ashui.ui;

import ashui.core.externs.LayoutTreeNative;
import ashui.layout.Element;
import ashui.layout.IntoReactive;
import ashui.layout.LayoutTree;
import ashui.layout.Prop;
import ashui.svg.SvgDocument;
import ashui.types.Color;

typedef SvgAttributes = {
	/** The size it is laid out at; the document's natural size by default. **/
	?width:IntoReactive<Single>,
	?height:IntoReactive<Single>,
	/** What `currentColor` is; inherited from the elements it is in by default, as text colour is. **/
	?color:IntoReactive<Color>
}

/**
	Draws an SVG image in its box, fitted and centred, rasterized at the size
	it covers on screen so it stays sharp when zoomed. A mask SVG, one drawn
	only in `currentColor`, takes the element's text colour, its own or the
	one it inherits, so classes such as `text-primary` on it or on anything
	around it, and transitions, colour it.

	In hxx, write the SVG itself: `<svg class="w-6 h-6 text-primary" viewBox="0 0 24 24"><path d="..."/></svg>`.
**/
class Svg extends Element {
	/** The parsed SVG it draws. **/
	public final document:SvgDocument;

	public function new(document:SvgDocument, ?attr:SvgAttributes, ?tree:LayoutTree) {
		super(tree);
		this.document = document;
		node = this.tree.createNode();
		ashui.css.Identity.register(this.tree, node.id, "svg");
		node.set(Prop.Width, attr != null && attr.width != null ? attr.width : (document.width : Single));
		node.set(Prop.Height, attr != null && attr.height != null ? attr.height : (document.height : Single));
		node.set(Prop.FlexShrink, (0 : Single));
		if (attr != null && attr.color != null)
			node.set(Prop.Color, attr.color);
		LayoutTreeNative.blinc_tree_set_image(this.tree.ptr, node.id, document.id);
	}
}
