package ashui.ui;

import ashui.input.Interaction;
import ashui.layout.Element;

typedef LabelProps = {
	/** The id of the control it labels; hxx's `for`. Without it, the label labels the first input inside it. **/
	?htmlFor:String,

	?id:String
}

/**
	HTML's `<label>`, built in: clicking it operates its control, the input
	whose id its `for` names, or else the first input inside it, as clicking
	the control itself would: a checkbox flips, a radio is checked, and the
	control takes focus.
**/
class Label extends Component<LabelProps> {
	function render():Element {
		var box = new Div({tag: "label", id: props.id}, children);
		Interaction.of(box.node).onClick(e -> {
			var control = target(box);
			// A click on the control itself already operated it.
			if (control == null || e.target == control.node)
				return;
			if (Std.isOfType(control.control, Input)) (cast control.control : Input).activate();
			@:privateAccess ashui.input.Focus.set(Interaction.of(control.node), false);
		});
		return box;
	}

	function controlAt(box:Div, id:haxe.Int64):Null<{node:ashui.layout.Node, control:FormControl}> {
		var input = Input.at(box.tree, id);
		if (input != null) return {node:input.node, control:input};
		var area = TextArea.at(id);
		if (area != null) return {node:area.node, control:area};
		var select = Select.at(id);
		return select == null ? null : {node:select.node, control:select};
	}

	/** The form control this label operates. **/
	function target(box:Div):Null<{node:ashui.layout.Node, control:FormControl}> {
		var tree = box.tree;
		if (props.htmlFor != null) {
			for (node => identity in @:privateAccess ashui.css.Identity.trees.get(tree))
				if (identity.id == props.htmlFor) {
					var input = controlAt(box, identity.node.id);
					if (input != null)
						return input;
				}
			return null;
		}
		var stack = [box.node.id];
		while (stack.length > 0) {
			var at = stack.shift();
			var input = controlAt(box, at);
			if (input != null)
				return input;
			for (child in tree.children(at))
				stack.push(child);
		}
		return null;
	}
}
