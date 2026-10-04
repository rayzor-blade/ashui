package ashui.components;

import ashui.ui.Component;
import ashui.layout.Element;

/** A ring turning while something is under way. CSS: `.ui-spinner`; `--ui-spinner-size`, `-width`, `-color`, `-track`. **/
class Spinner extends Component<{?id:String}> {
	function render():Element
		return Library.part("ui-spinner", null, null, null, props.id);
}
