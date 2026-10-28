package ashui.components;

import ashui.layout.Element;
import ashui.layout.IntoReactive;
import ashui.ui.Component;

typedef CheckboxProps = {
	/** Checked state. A supplied signal is read and updated; a constant sets the initial state. **/
	?checked:IntoReactive<Bool>,
	?indeterminate:IntoReactive<Bool>,
	?disabled:IntoReactive<Bool>,
	?required:Bool,
	/** Small, medium (default), or large box and label (e8a1b50). **/
	?size:Size,
	?name:String,
	?id:String,
	/** Receives the checked state after a user change. **/
	?onChange:Bool->Void
}

/**
	A checkbox with a clickable label supplied by its children.
	Wraps the built-in checkbox input in a label so clicking the text toggles
	the checkbox. CSS: `.ui-checkbox-field` with `[data-disabled]`,
	`.ui-checkbox` with `:checked`, `:indeterminate`, and `:disabled`,
	and `.ui-checkbox-text`.
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
		var size = props.size == null ? Size.Md : props.size;
		ashui.css.Identity.of(box.tree, box.node.id).addClasses(["ui-checkbox"]).setAttribute("data-size", size);
		if (children.length == 0)
			return box;
		var text = Library.part("ui-checkbox-text", null, null, children);
		ashui.text.InlineFlow.attach(text);
		var field = new ashui.ui.Label({}, [box, text]);
		var identity = ashui.css.Identity.of(field.tree, field.node.id);
		identity.addClasses(["ui-checkbox-field"]).setAttribute("data-size", size);
		if (props.disabled != null)
			identity.bindAttribute("data-disabled", ashui.reactive.Computed.make(() -> (ashui.input.Interaction.of(box.node).disabled.get() ? "" : null : Null<String>)));
		return field;
	}
}
