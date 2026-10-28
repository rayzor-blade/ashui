package ashui.components;

import ashui.ui.Component;
import ashui.layout.Element;

/** A rotating ring for work in progress. CSS: `.ui-spinner[data-size]`; variables: `--ui-spinner-size`, `-width`, `-color`, and `-track`. **/
class Spinner extends Component<{?size:Size, ?id:String}> {
	function render():Element
		return Library.part("ui-spinner", null, ["size" => (props.size == null ? Size.Md : props.size : String)], null, props.id);
}
