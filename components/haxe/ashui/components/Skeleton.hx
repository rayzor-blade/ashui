package ashui.components;

import ashui.ui.Component;
import ashui.layout.Element;

/**
	A placeholder where content is loading, a highlight sweeping across it;
	size it with the element's own width and height. CSS: `.ui-skeleton`;
	`--ui-skeleton-bg`, `-highlight`, `-radius`, `-duration`.
**/
class Skeleton extends Component<{?id:String}> {
	function render():Element
		return Library.part("ui-skeleton", null, null, children, props.id);
}
