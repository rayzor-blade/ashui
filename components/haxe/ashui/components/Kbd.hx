package ashui.components;

import ashui.layout.Element;
import ashui.ui.Component;

/** A keycap label, such as `<kbd>⌘</kbd><kbd>K</kbd>`. CSS: `.ui-kbd` with `[data-size]`. **/
class Kbd extends Component<{?size:Size, ?id:String}> {
	function render():Element
		return Library.part("ui-kbd", "kbd", ["size" => (props.size == null ? Size.Md : props.size : String)], children, props.id);
}
