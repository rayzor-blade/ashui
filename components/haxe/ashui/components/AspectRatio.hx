package ashui.components;

import ashui.layout.Element;
import ashui.ui.Component;

/**
	A box kept at a width-to-height `ratio` (16 / 9 by default), its height
	following its width; what it holds fills it. CSS: `.ui-aspect-ratio`,
	whose `aspect-ratio` a stylesheet may set instead.
**/
class AspectRatio extends Component<{?ratio:Float, ?id:String}> {
	function render():Element {
		var box = Library.part("ui-aspect-ratio", null, null, children, props.id);
		box.node.set(ashui.layout.Prop.AspectRatio, props.ratio == null ? 16 / 9 : props.ratio);
		return box;
	}
}
