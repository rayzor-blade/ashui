package ashui.components;

import ashui.layout.Element;
import ashui.ui.Component;

/**
	Overlapping avatars in a row, outlined with the page color. When `max`
	is exceeded, a count badge represents the remaining avatars.
	CSS: `.ui-avatar-group`, `[data-size]`, and `.ui-avatar-more`.
**/
class AvatarGroup extends Component<{?max:Int, ?size:String, ?id:String}> {
	function render():Element {
		var shown = props.max == null ? children : children.slice(0, props.max);
		var parts = shown.copy();
		if (props.max != null && children.length > props.max)
			parts.push(Library.part("ui-avatar-more", null, null, [new ashui.ui.Text('+${children.length - props.max}')]));
		return Library.part("ui-avatar-group", null, props.size == null ? null : ["size" => props.size], parts, props.id);
	}
}
