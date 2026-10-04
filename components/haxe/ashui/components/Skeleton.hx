package ashui.components;

import ashui.ui.Component;
import ashui.layout.Element;

/** A placeholder pulsing where content is loading; size it with the element's own width and height. CSS: `.ui-skeleton`; `--ui-skeleton-bg`, `-radius`. **/
class Skeleton extends Component<{?id:String}> {
	function render():Element
		return Library.part("ui-skeleton", null, null, children, props.id);
}
