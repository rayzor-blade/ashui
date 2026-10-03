package ashui.ui;

import ashui.layout.Element;

typedef OptionProps = {
	/** What the select holds while it is chosen; its label when left out, as HTML's. **/
	?value:String,

	/** What the select shows for it; its text when left out. **/
	?label:String,

	?disabled:Bool
}

/**
	HTML's `<option>`, inside a `<select>` or an `<optgroup>`: a choice, its
	label the text it holds. The select draws it in its list of options as
	an element of type `option`, `:checked` while it is the select's value.
**/
class Option extends Component<OptionProps> {
	function render():Element
		return new Div({tag: "option", display: ashui.types.Style.Display.None}, children);

	/** What the select shows for it. **/
	public function labelText():String {
		if (props.label != null)
			return props.label;
		var out = new StringBuf();
		for (c in children)
			if (Std.isOfType(c, Text))
				out.add((cast c : Text).text());
		return StringTools.trim(out.toString());
	}

	/** What the select holds while it is chosen. **/
	public function valueText():String
		return props.value != null ? props.value : labelText();

	public function isDisabled():Bool
		return props.disabled == true;
}
