package ashui.components;

import ashui.ui.Component;
import ashui.layout.Element;
import ashui.types.Bitmap;

typedef AvatarProps = {
	/** `sm`, `md` (the default) or `lg`. **/
	?size:String,
	?id:String
}

/**
	A person's picture, an `AvatarImage`, or their initials in an
	`AvatarFallback` when it has none: the fallback shows only without an
	image. CSS: `.ui-avatar`, `[data-size]`, `.ui-avatar-image`,
	`.ui-avatar-fallback`; `--ui-avatar-size`, `-radius`, `-bg`, `-fg`.
**/
class Avatar extends Component<AvatarProps> {
	function render():Element
		return Library.part("ui-avatar", null, ["size" => props.size == null ? "md" : props.size], children, props.id);
}

/** An avatar's picture, covering it. **/
class AvatarImage extends Component<{bitmap:Bitmap}> {
	function render():Element {
		Library.use();
		var image = new ashui.ui.Image(props.bitmap, {fit: Cover});
		var identity = ashui.css.Identity.of(image.tree, image.node.id);
		identity.setClasses(["ui-avatar-image"]);
		return image;
	}
}

/** An avatar's initials, shown while it has no picture. **/
class AvatarFallback extends Component<{?id:String}> {
	function render():Element
		return Library.part("ui-avatar-fallback", null, null, children, props.id);
}
