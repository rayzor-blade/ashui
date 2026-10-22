package ashui.ui;

import ashui.core.externs.LayoutTreeNative;
import ashui.layout.Element;
import ashui.layout.IntoReactive;
import ashui.layout.LayoutTree;
import ashui.layout.Prop;
import ashui.types.Bitmap;
import ashui.types.ObjectFit;

/** Fractions of the free space, plus pixel offsets; percentages remain exact until drawing. **/
typedef ImagePosition = ashui.types.ImagePosition;

typedef ImageAttributes = {
	/** The size it is laid out at; the bitmap's own by default. **/
	?width:IntoReactive<Single>,
	?height:IntoReactive<Single>,
	/** How the bitmap fills a box of another shape, as CSS's `object-fit`; `Fill` by default, as an `<img>`'s. **/
	?fit:ObjectFit,
	/** The same positioning as CSS object-position; centered by default. **/
	?objectPosition:ImagePosition
}

/**
	Draws a `Bitmap` in its box, resampled to the size it covers on screen,
	fitted as `fit` says: stretched by default, or letterboxed whole
	(`Contain`) or cropped to cover the box (`Cover`). `None` keeps its
	intrinsic size; `ScaleDown` contains it without enlargement. Positioning
	defaults to the center and follows CSS object-position.
**/
class Image extends Element {
	static final byNode = new haxe.ds.ObjectMap<ashui.layout.Node, Image>();
	static var hooked = false;

	final authoredFit:Bool;
	final authoredPosition:Bool;
	var fitted:ObjectFit;
	var positioned:ImagePosition;
	var resident = true;
	var mapped = -1;

	static final CENTER:ImagePosition = {
		x: 0.5,
		y: 0.5,
		offsetX: 0,
		offsetY: 0
	};

	/** CSS object-fit through the existing bitmap renderer. **/
	@:noCompletion public static function cssFit(value:String):ObjectFit {
		return switch StringTools.trim(value).toLowerCase() {
			case "cover": Cover;
			case "contain": Contain;
			case "fill": Fill;
			case "none": None;
			case "scale-down": ScaleDown;
			case _: throw "object-fit supports cover, contain, fill, none or scale-down";
		};
	}

	static function hook():Void {
		if (hooked)
			return;
		hooked = true;
		ashui.css.Css.restyled.push(identity -> {
			var image = byNode.get(identity.node);
			if (image == null)
				return;
			var value = ashui.css.Css.resolved(identity, "object-fit");
			var fit:ObjectFit = value == null ? Fill : try cssFit(value) catch (_:String) Fill;
			styleFit(identity.node, fit);
			if (ashui.css.Css.resolved(identity, "object-position") == null)
				stylePosition(identity.node, CENTER);
		});
		ashui.css.Identity.forgetHooks.push(identity -> byNode.remove(identity.node));
	}

	/** Applies fitting without overriding the element's own fit attribute or utility. **/
	@:noCompletion public static function styleFit(node:ashui.layout.Node, fit:ObjectFit):Void {
		var image = byNode.get(node);
		if (image == null || image.authoredFit || image.fitted == fit)
			return;
		image.fitted = fit;
		image.applyMapping();
	}

	@:noCompletion public static function stylePosition(node:ashui.layout.Node, position:ImagePosition):Void {
		var image = byNode.get(node);
		if (image == null || image.authoredPosition)
			return;
		var old = image.positioned;
		if (old.x == position.x && old.y == position.y && old.offsetX == position.offsetX && old.offsetY == position.offsetY)
			return;
		image.positioned = position;
		image.applyMapping();
	}

	function applyMapping():Void {
		if (!resident) return;
		// The slot protocol stays four fits per bitmap. Additional object modes
		// sample its existing Fill slot and carry geometry separately.
		var fit:ashui.types.Brush.ImageFit = (fitted : Int) >= 4 ? Fill : cast fitted;
		mapped = bitmap.imageSlotFor(fit);
		LayoutTreeNative.blinc_tree_set_image(tree.ptr, node.id, mapped);
		LayoutTreeNative.blinc_tree_set_image_mapping(tree.ptr, node.id, fitted, positioned.x, positioned.y, positioned.offsetX, positioned.offsetY);
		tree.markDrawn();
	}

	function setResident(value:Bool):Void {
		if (!value) {
			if (resident) LayoutTreeNative.blinc_tree_set_image(tree.ptr, node.id, -1);
			resident = false;
			mapped = -1;
		} else {
			resident = true;
			var fit:ashui.types.Brush.ImageFit = (fitted : Int) >= 4 ? Fill : cast fitted;
			if (mapped != bitmap.imageSlotFor(fit)) applyMapping();
		}
	}

	/** The image it draws. **/
	public final bitmap:Bitmap;

	public function new(bitmap:Bitmap, ?attr:ImageAttributes, ?tree:LayoutTree) {
		super(tree);
		hook();
		this.bitmap = bitmap;
		authoredFit = attr != null && attr.fit != null;
		fitted = authoredFit ? attr.fit : Fill;
		authoredPosition = attr != null && attr.objectPosition != null;
		positioned = authoredPosition ? attr.objectPosition : CENTER;
		if ((fitted : Int) < 0 || (fitted : Int) > 5)
			throw "invalid object fit";
		if (!Math.isFinite(positioned.x) || !Math.isFinite(positioned.y) || !Math.isFinite(positioned.offsetX) || !Math.isFinite(positioned.offsetY))
			throw "object position must be finite";
		node = this.tree.createNode();
		byNode.set(node, this);
		var originalNode = node;
		ashui.reactive.Owner.onCleanup(() -> byNode.remove(originalNode));
		ashui.css.Identity.register(this.tree, node, "img");
		node.set(Prop.Width, attr != null && attr.width != null ? attr.width : (bitmap.width : Single));
		node.set(Prop.Height, attr != null && attr.height != null ? attr.height : (bitmap.height : Single));
		node.set(Prop.FlexShrink, (0 : Single));
		applyMapping();
		ImageResidency.register(node, bitmap, setResident);
	}
}
