package ashui.components;

import ashui.ui.Component;
import ashui.layout.Element;

/** A ring turning while something is under way. CSS: `.ui-spinner`, `[data-size]`; `--ui-spinner-size`, `-width`, `-color`, `-track`. **/
class Spinner extends Component<{?size:Size, ?id:String}> {
	function render():Element
		return Library.part("ui-spinner", null, ["size" => (props.size == null ? Size.Md : props.size : String)], null, props.id);
}
