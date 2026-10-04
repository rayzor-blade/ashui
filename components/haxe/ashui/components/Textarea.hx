package ashui.components;

import ashui.layout.Element;
import ashui.ui.Component;

/** A text area in the library's look: the built-in `<textarea>` with the class `ui-textarea`. **/
class Textarea extends Component<ashui.ui.TextArea.TextAreaProps> {
	function render():Element {
		Library.use();
		var el = new ashui.ui.TextArea(props);
		ashui.css.Identity.of(el.tree, el.node.id).addClasses(["ui-textarea"]);
		return el;
	}
}
