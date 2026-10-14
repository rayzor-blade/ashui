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
	static final intrinsic = new haxe.ds.ObjectMap<ashui.css.Identity, Svg>();
	static var intrinsicHook = false;

	final naturalWidth:Bool;
	final naturalHeight:Bool;

	/** The parsed SVG it draws. **/
	public final document:SvgDocument;

	public function new(document:SvgDocument, ?attr:SvgAttributes, ?tree:LayoutTree) {
		super(tree);
		this.document = document;
		naturalWidth = attr == null || attr.width == null;
		naturalHeight = attr == null || attr.height == null;
		node = this.tree.createNode();
		var identity = ashui.css.Identity.register(this.tree, node, "svg");
		// Intrinsic dimensions are defaults; explicit attributes still win over CSS (git-bug e8a1b50).
		if (attr != null && attr.width != null)
			node.set(Prop.Width, attr.width);
		else
			@:privateAccess node.style(Prop.Width, (document.width : Single));
		if (attr != null && attr.height != null)
			node.set(Prop.Height, attr.height);
		else
			@:privateAccess node.style(Prop.Height, (document.height : Single));
		if (naturalWidth || naturalHeight) {
			intrinsic.set(identity, this);
			ashui.reactive.Owner.onCleanup(() -> intrinsic.remove(identity));
			if (!intrinsicHook) {
				intrinsicHook = true;
				ashui.css.Css.restyled.push(identity -> {
					var svg = intrinsic.get(identity);
					if (svg != null)
						svg.restoreIntrinsic(identity);
				});
			}
		}
		node.set(Prop.FlexShrink, (0 : Single));
		if (attr != null && attr.color != null)
			node.set(Prop.Color, attr.color);
		LayoutTreeNative.blinc_tree_set_image(this.tree.ptr, node.id, document.id);
	}

	/** Removing a size rule restores the document's dimensions, without owning them (e8a1b50). **/
	function restoreIntrinsic(identity:ashui.css.Identity):Void {
		var width = ashui.css.Css.computed(identity, "width"),
			height = ashui.css.Css.computed(identity, "height");
		if (naturalWidth && (width == null || width == "auto"))
			@:privateAccess node.style(Prop.Width, (document.width : Single));
		if (naturalHeight && (height == null || height == "auto"))
			@:privateAccess node.style(Prop.Height, (document.height : Single));
	}
}
