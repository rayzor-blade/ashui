package ashui.components;

import ashui.layout.Element;
import ashui.ui.Component;

typedef TextareaProps = {
	> ashui.ui.TextArea.TextAreaProps,
	/** Small, medium (default) or large density; explicit width/height still apply (git-bug e8a1b50). **/
	?size:Size
}

/** A text area in the library's look: the built-in `<textarea>` with the class `ui-textarea` and `data-size`. **/
class Textarea extends Component<TextareaProps> {
	function render():Element {
		Library.use();
		var el = new ashui.ui.TextArea(props);
		ashui.css.Identity.of(el.tree, el.node.id).addClasses(["ui-textarea"]).setAttribute("data-size", props.size == null ? Size.Md : props.size);
		return el;
	}
}
