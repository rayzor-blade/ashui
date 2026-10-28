package ashui.components;

import ashui.layout.Element;
import ashui.ui.Component;

/**
	A container with a fixed width-to-height ratio. Defaults to 16:9; height
	follows width and children fill the container. Style `.ui-aspect-ratio`
	or set its CSS `aspect-ratio` to override the ratio.
**/
class AspectRatio extends Component<{?ratio:Float, ?id:String}> {
	function render():Element {
		var box = Library.part("ui-aspect-ratio", null, null, children, props.id);
		box.node.set(ashui.layout.Prop.AspectRatio, props.ratio == null ? 16 / 9 : props.ratio);
		return box;
	}
}
