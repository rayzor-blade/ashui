package ashui.ui;

import ashui.layout.Element;

typedef OptgroupProps = {
	/** Heading displayed above the options. **/
	label:String,

	/** Disables every option in this group. **/
	?disabled:Bool
}

/** A labeled group of options inside a `<select>`, written as `<optgroup>` in HXX. **/
class Optgroup extends Component<OptgroupProps> {
	function render():Element {
		var box = new Div({tag: "optgroup", display: ashui.types.Style.Display.None}, children);
		Select.register(this, box);
		return box;
	}

	/** Returns the current options, including those supplied by `<for>` and `<if>`. **/
	public function options():Array<Option> {
		var out:Array<Option> = [];
		for (c in children)
			Select.walk(tree, c.node.id, this, (o, _) -> out.push(o));
		return out;
	}
}
