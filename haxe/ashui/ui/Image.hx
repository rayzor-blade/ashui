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
	/** The image it draws. **/
	public final bitmap:Bitmap;

	public function new(bitmap:Bitmap, ?attr:ImageAttributes, ?tree:LayoutTree) {
		super(tree);
		this.bitmap = bitmap;
		node = this.tree.createNode();
		ashui.css.Identity.register(this.tree, node, "img");
		node.set(Prop.Width, attr != null && attr.width != null ? attr.width : (bitmap.width : Single));
		node.set(Prop.Height, attr != null && attr.height != null ? attr.height : (bitmap.height : Single));
		node.set(Prop.FlexShrink, (0 : Single));
		var fit:ImageFit = attr != null && attr.fit != null ? attr.fit : Fill;
		LayoutTreeNative.blinc_tree_set_image(this.tree.ptr, node.id, bitmap.slotFor(fit));
	}
}
