package ashui.ui;

import ashui.core.externs.LayoutTreeNative;
import ashui.layout.Element;
import ashui.layout.IntoReactive;
import ashui.layout.LayoutTree;
import ashui.layout.Prop;
import ashui.svg.SvgDocument;
import ashui.types.Color;

typedef SvgAttributes = {
	/** Display width in layout units. Defaults to the SVG document width. **/
	?width:IntoReactive<Single>,
	?height:IntoReactive<Single>,
	/** Color used by SVG `currentColor`. Inherits the parent text color when omitted. **/
	?color:IntoReactive<Color>
}

/**
	Displays an SVG, fitted and centered in its box.

	Rasterization uses the on-screen size to keep zoomed images sharp. SVGs
	drawn only with `currentColor` follow the element text color, including
	inherited colors, CSS utilities such as `text-primary`, and transitions.

	Write SVG directly in HXX:
	`<svg class="w-6 h-6 text-primary" viewBox="0 0 24 24"><path d="..."/></svg>`.
**/
class Svg extends Element {
	static final intrinsic = new haxe.ds.ObjectMap<ashui.css.Identity, Svg>();
	static var intrinsicHook = false;

	final naturalWidth:Bool;
	final naturalHeight:Bool;

	/** The parsed source SVG. **/
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
		ImageResidency.register(node, null, _ -> {});
	}

	/** Restores intrinsic dimensions when a size rule is removed, without claiming inline ownership (e8a1b50). **/
	function restoreIntrinsic(identity:ashui.css.Identity):Void {
		var width = ashui.css.Css.computed(identity, "width"),
			height = ashui.css.Css.computed(identity, "height");
		if (naturalWidth && (width == null || width == "auto"))
			@:privateAccess node.style(Prop.Width, (document.width : Single));
		if (naturalHeight && (height == null || height == "auto"))
			@:privateAccess node.style(Prop.Height, (document.height : Single));
	}
}
