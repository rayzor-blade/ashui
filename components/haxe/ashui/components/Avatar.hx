package ashui.components;

import ashui.ui.Component;
import ashui.layout.Element;
import ashui.types.Bitmap;

typedef AvatarProps = {
	/** Avatar size: `sm`, `md` (default), or `lg`. **/
	?size:String,
	?id:String
}

/**
	A profile image with an initials fallback.
	Use `AvatarImage` for the picture and `AvatarFallback` when no image
	is supplied. CSS: `.ui-avatar`, `[data-size]`, `.ui-avatar-image`, and
	`.ui-avatar-fallback`; variables: `--ui-avatar-size`, `-radius`, `-bg`, `-fg`.
**/
class Avatar extends Component<AvatarProps> {
	function render():Element
		return Library.part("ui-avatar", null, ["size" => props.size == null ? "md" : props.size], children, props.id);
}

/** An image cropped to cover the avatar. **/
class AvatarImage extends Component<{bitmap:Bitmap}> {
	function render():Element {
		Library.use();
		var image = new ashui.ui.Image(props.bitmap, {fit: Cover});
		var identity = ashui.css.Identity.of(image.tree, image.node.id);
		identity.setClasses(["ui-avatar-image"]);
		return image;
	}
}

/** Initials or other content shown when no avatar image is supplied. **/
class AvatarFallback extends Component<{?id:String}> {
	function render():Element
		return Library.part("ui-avatar-fallback", null, null, children, props.id);
}
