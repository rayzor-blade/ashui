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
	function render():Element {
		var box = new Div({tag: "optgroup", display: ashui.types.Style.Display.None}, children);
		Select.register(this, box);
		return box;
	}

	/** The options in it now, those a `<for>` or `<if>` holds included. **/
	public function options():Array<Option> {
		var out:Array<Option> = [];
		for (c in children)
			Select.walk(tree, c.node.id, this, (o, _) -> out.push(o));
		return out;
	}
}
