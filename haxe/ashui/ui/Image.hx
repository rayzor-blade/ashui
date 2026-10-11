package ashui.ui;

import ashui.core.externs.LayoutTreeNative;
import ashui.layout.Element;
import ashui.layout.IntoReactive;
import ashui.layout.LayoutTree;
import ashui.layout.Prop;
import ashui.types.Bitmap;
import ashui.types.Brush.ImageFit;

typedef ImageAttributes = {
	/** The size it is laid out at; the bitmap's own by default. **/
	?width:IntoReactive<Single>,
	?height:IntoReactive<Single>,
	/** How the bitmap fills a box of another shape, as CSS's `object-fit`; `Fill` by default, as an `<img>`'s. **/
	?fit:ImageFit
}

/**
	Draws a `Bitmap` in its box, resampled to the size it covers on screen,
	fitted as `fit` says: stretched by default, or letterboxed whole
	(`Contain`) or cropped to cover the box (`Cover`), centred.
**/
class Image extends Element {
	static final byNode = new haxe.ds.ObjectMap<ashui.layout.Node, Image>();
	static var hooked = false;
	final authoredFit:Bool;
	var fitted:ImageFit;

	/** The image modes supported by the existing bitmap renderer. **/
	@:noCompletion public static function cssFit(value:String):ImageFit {
		return switch StringTools.trim(value).toLowerCase() {
			case "cover": Cover;
			case "contain": Contain;
			case "fill": Fill;
			case _: throw "object-fit supports cover, contain or fill";
		};
	}

	static function hook():Void {
		if (hooked) return;
		hooked = true;
		ashui.css.Css.restyled.push(identity -> {
			var image = byNode.get(identity.node);
			if (image == null || image.authoredFit) return;
			var value = ashui.css.Css.resolved(identity, "object-fit");
			var fit:ImageFit = value == null ? Fill : try cssFit(value) catch (_:String) Fill;
			styleFit(identity.node, fit);
		});
		ashui.css.Identity.forgetHooks.push(identity -> byNode.remove(identity.node));
	}

	/** Applies fitting without overriding the element's own fit attribute or utility. **/
	@:noCompletion public static function styleFit(node:ashui.layout.Node, fit:ImageFit):Void {
		var image = byNode.get(node);
		if (image == null || image.authoredFit || image.fitted == fit) return;
		image.fitted = fit;
		LayoutTreeNative.blinc_tree_set_image(image.tree.ptr, image.node.id, image.bitmap.slotFor(fit));
		image.tree.markDrawn();
	}

	/** The image it draws. **/
	public final bitmap:Bitmap;

	public function new(bitmap:Bitmap, ?attr:ImageAttributes, ?tree:LayoutTree) {
		super(tree);
		hook();
		this.bitmap = bitmap;
		authoredFit = attr != null && attr.fit != null;
		fitted = authoredFit ? attr.fit : Fill;
		node = this.tree.createNode();
		byNode.set(node, this);
		var originalNode = node;
		ashui.reactive.Owner.onCleanup(() -> byNode.remove(originalNode));
		ashui.css.Identity.register(this.tree, node, "img");
		node.set(Prop.Width, attr != null && attr.width != null ? attr.width : (bitmap.width : Single));
		node.set(Prop.Height, attr != null && attr.height != null ? attr.height : (bitmap.height : Single));
		node.set(Prop.FlexShrink, (0 : Single));
		LayoutTreeNative.blinc_tree_set_image(this.tree.ptr, node.id, bitmap.slotFor(fitted));
	}
}
