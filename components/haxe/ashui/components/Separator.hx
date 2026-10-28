package ashui.components;

import ashui.ui.Component;
import ashui.layout.Element;

typedef SeparatorProps = {
	/** Rule direction: `horizontal` (default) across the container, or `vertical` along its height. **/
	?orientation:String,
	?id:String
}

/** A divider between groups of content. CSS: `.ui-separator`, `[data-orientation]`, `--ui-separator-color`, and `--ui-separator-size`. **/
class Separator extends Component<SeparatorProps> {
	function render():Element
		return Library.part("ui-separator", null, ["orientation" => props.orientation == "vertical" ? "vertical" : "horizontal"], null, props.id);
}
