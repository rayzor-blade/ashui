package ashui.components;

import ashui.layout.Element;
import ashui.ui.Component;

typedef LabelProps = {
	/** ID of the associated control, written as `for` in HXX. Defaults to the first input inside the label. **/
	?htmlFor:String,
	/** Adds an asterisk to indicate a required field. **/
	?required:Bool,
	?id:String
}

/**
	A themed form label. Clicking activates the associated control through
	the built-in label behavior. CSS: `.ui-label` and `.ui-label-required`.
**/
class Label extends Component<LabelProps> {
	function render():Element {
		var text = Library.part("ui-label-text", null, null, children);
		ashui.text.InlineFlow.attach(text);
		var parts:Array<Element> = [text];
		if (props.required == true)
			parts.push(Library.part("ui-label-required", "span", null, [new ashui.ui.Text("*")]));
		var el = new ashui.ui.Label({htmlFor: props.htmlFor, id: props.id}, parts);
		ashui.css.Identity.of(el.tree, el.node.id).addClasses(["ui-label"]);
		return el;
	}
}
