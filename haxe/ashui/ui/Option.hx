package ashui.ui;

import ashui.layout.Element;

typedef OptionProps = {
	/** Selected value stored by the select. Defaults to the option label. **/
	?value:String,

	/** Display label. Defaults to the option text. **/
	?label:String,

	?disabled:Bool
}

/**
	A choice inside a `<select>` or `<optgroup>`, written as `<option>` in HXX.
	The select displays the option label and applies `:checked` to the selected
	option in the open list.
**/
class Option extends Component<OptionProps> {
	function render():Element {
		var box = new Div({tag: "option", display: ashui.types.Style.Display.None}, children);
		Select.register(this, box);
		return box;
	}

	/** Returns the display label. **/
	public function labelText():String {
		if (props.label != null)
			return props.label;
		var out = new StringBuf();
		for (c in children)
			if (Std.isOfType(c, Text))
				out.add((cast c : Text).text());
		return StringTools.trim(out.toString());
	}

	/** Returns the value stored when this option is selected. **/
	public function valueText():String
		return props.value != null ? props.value : labelText();

	public function isDisabled():Bool
		return props.disabled == true;
}
