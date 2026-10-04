package ashui.components;

import ashui.layout.Element;
import ashui.ui.Component;

/** A key, as a keycap: `<kbd>⌘</kbd><kbd>K</kbd>`. CSS: `.ui-kbd` (`[data-size]`). **/
class Kbd extends Component<{?size:Size, ?id:String}> {
	function render():Element
		return Library.part("ui-kbd", "kbd", ["size" => (props.size == null ? Size.Md : props.size : String)], children, props.id);
}
