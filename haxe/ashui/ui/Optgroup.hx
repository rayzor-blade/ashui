package ashui.ui;

import ashui.layout.Element;

typedef OptgroupProps = {
	/** The heading over its options. **/
	label:String,

	/** Disables every option in it. **/
	?disabled:Bool
}

/** HTML's `<optgroup>`: options under a heading in a select's list. **/
class Optgroup extends Component<OptgroupProps> {
	function render():Element
		return new Div({tag: "optgroup", display: ashui.types.Style.Display.None}, children);

	/** The options in it. **/
	public function options():Array<Option>
		return [for (c in children) if (Std.isOfType(c, Option)) (cast c : Option)];
}
