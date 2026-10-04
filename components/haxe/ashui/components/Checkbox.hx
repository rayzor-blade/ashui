package ashui.components;

import ashui.layout.Element;
import ashui.layout.IntoReactive;
import ashui.ui.Component;

typedef CheckboxProps = {
	/** Whether it is checked. A signal is read and written; a constant sets it once. **/
	?checked:IntoReactive<Bool>,
	?indeterminate:IntoReactive<Bool>,
	?disabled:IntoReactive<Bool>,
	?required:Bool,
	?name:String,
	?id:String,
	/** Called with whether it is checked after the user changes it. **/
	?onChange:Bool->Void
}

/**
	A checkbox with its label: the built-in `<input type="checkbox">` inside
	a `<label>`, so a press on the text checks it too. Its children are the
	label's text. CSS: `.ui-checkbox-field` (the label, `[data-disabled]`),
	`.ui-checkbox` (the box, `:checked`, `:indeterminate`, `:disabled`),
	`.ui-checkbox-text`.
**/
class Checkbox extends Component<CheckboxProps> {
	function render():Element {
		Library.use();
		var box = new ashui.ui.Input({
			type: "checkbox",
			checked: props.checked,
			indeterminate: props.indeterminate,
			disabled: props.disabled,
			required: props.required,
			name: props.name,
			id: props.id,
			onChange: props.onChange
		});
		ashui.css.Identity.of(box.tree, box.node.id).addClasses(["ui-checkbox"]);
		if (children.length == 0)
			return box;
		var text = Library.part("ui-checkbox-text", null, null, children);
		ashui.text.InlineFlow.attach(text);
		var field = new ashui.ui.Label({}, [box, text]);
		var identity = ashui.css.Identity.of(field.tree, field.node.id);
		identity.addClasses(["ui-checkbox-field"]);
		if (props.disabled != null)
			identity.bindAttribute("data-disabled", ashui.reactive.Computed.make(() -> (ashui.input.Interaction.of(box.node).disabled.get() ? "" : null : Null<String>)));
		return field;
	}
}
