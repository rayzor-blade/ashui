package ashui.components;

import ashui.ui.Component;
import ashui.layout.Element;

typedef SeparatorProps = {
	/** `horizontal` (the default), a rule across what holds it, or `vertical`, a rule down it. **/
	?orientation:String,
	?id:String
}

/** A rule between groups of content. CSS: `.ui-separator`, `[data-orientation]`; `--ui-separator-color`, `-size`. **/
class Separator extends Component<SeparatorProps> {
	function render():Element
		return Library.part("ui-separator", null, ["orientation" => props.orientation == "vertical" ? "vertical" : "horizontal"], null, props.id);
}
