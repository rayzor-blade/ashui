package ashui.components;

import ashui.layout.Element;
import ashui.ui.Component;

typedef TextareaProps = {
	> ashui.ui.TextArea.TextAreaProps,
	/** Small, medium (default), or large sizing. Explicit width and height still apply (e8a1b50). **/
	?size:Size
}

/** A themed multiline text input. Uses the built-in text area behavior and exposes `.ui-textarea[data-size]`. **/
class Textarea extends Component<TextareaProps> {
	function render():Element {
		Library.use();
		var el = new ashui.ui.TextArea(props);
		ashui.css.Identity.of(el.tree, el.node.id).addClasses(["ui-textarea"]).setAttribute("data-size", props.size == null ? Size.Md : props.size);
		return el;
	}
}
