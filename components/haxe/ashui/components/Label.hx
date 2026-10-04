package ashui.components;

import ashui.layout.Element;
import ashui.ui.Component;

typedef LabelProps = {
	/** The id of the control it labels; hxx's `for`. Without it, the first input inside it. **/
	?htmlFor:String,
	/** Marks the field as required, with an asterisk after the text. **/
	?required:Bool,
	?id:String
}

/**
	A field's label in the library's look: the built-in `<label>`, so a
	press on it operates its control, its text a flow. CSS: `.ui-label`,
	`.ui-label-required`.
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
