package ashui.components;

import ashui.ui.Component;
import ashui.layout.Element;

/**
	A loading placeholder with a sweeping highlight. Set width and height
	to match the expected content. CSS: `.ui-skeleton`; variables:
	`--ui-skeleton-bg`, `-highlight`, `-radius`, and `-duration`.
**/
class Skeleton extends Component<{?id:String}> {
	function render():Element
		return Library.part("ui-skeleton", null, null, children, props.id);
}
