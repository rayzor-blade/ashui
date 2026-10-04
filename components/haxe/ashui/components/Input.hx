package ashui.components;

import ashui.layout.Element;
import ashui.ui.Component;

/**
	A text field in the library's look: the built-in `<input>`, its
	constraints, validity and forms as they are, with the class `ui-input`.
	It takes every prop the built-in does. A checkbox, radio or range typed
	here gets the class of the library's own (`ui-checkbox`, `ui-radio`,
	`ui-slider`); `Checkbox`, `RadioGroup` and `Slider` lay those out with
	their labels. CSS: `.ui-input` (`:hover`, `:focus`, `:disabled`,
	`:user-invalid`); `--ui-input-bg`, `-border`, `-radius`, `-height`,
	`-padding`.
**/
class Input extends Component<ashui.ui.Input.InputProps> {
	function render():Element {
		Library.use();
		var el = new ashui.ui.Input(props);
		var cls = switch (props.type == null ? "text" : props.type.toLowerCase()) {
			case "checkbox": "ui-checkbox";
			case "radio": "ui-radio";
			case "range": "ui-slider";
			case _: "ui-input";
		}
		ashui.css.Identity.of(el.tree, el.node.id).addClasses([cls]);
		return el;
	}
}
