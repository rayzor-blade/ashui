package ashui.components;

import ashui.ui.Component;
import ashui.input.Events;
import ashui.input.Interaction;
import ashui.layout.Element;
import ashui.layout.IntoReactive;

enum abstract ButtonVariant(String) to String {
	var Primary = "primary";
	var Secondary = "secondary";
	var Destructive = "destructive";
	var Outline = "outline";
	var Ghost = "ghost";
	var Link = "link";
}

enum abstract ButtonSize(String) to String {
	var Sm = "sm";
	var Md = "md";
	var Lg = "lg";
	/** Square size for an icon-only button. **/
	var Icon = "icon";
}

typedef ButtonProps = {
	?variant:ButtonVariant,
	?size:ButtonSize,
	?disabled:IntoReactive<Bool>,
	/** Form action: `submit` (default), `reset`, or `button`. **/
	?type:String,
	/** Submit button name. The associated `value` is included in `FormData` and supplies the result for `method="dialog"`. **/
	?name:String,
	?value:String,
	?onClick:PointerEvent->Void,
	?id:String
}

/**
	A styled button with built-in focus, Enter/Space activation and form submission.

	Variants: primary, secondary, destructive, outline, ghost and link.
	Sizes: sm, md, lg and icon.
	CSS targets: `.ui-button`, `[data-variant]` and `[data-size]`.

	Customize with `--ui-button-bg`, `-bg-hover`, `-bg-active`, `-fg`,
	`-border`, `-height`, `-padding`, `-radius`, `-gap` and `-font-size`.
**/
class Button extends Component<ButtonProps> {
	function render():Element {
		var box = Library.part("ui-button", "button", [
			"variant" => (props.variant == null ? Primary : props.variant : String),
			"size" => (props.size == null ? Md : props.size : String)
		], children, props.id);
		if (props.type != null)
			ashui.css.Identity.of(box.tree, box.node.id).setAttribute("type", props.type);
		if (props.name != null)
			ashui.css.Identity.of(box.tree, box.node.id).setAttribute("name", props.name);
		if (props.value != null)
			ashui.css.Identity.of(box.tree, box.node.id).setAttribute("value", props.value);
		var i = Interaction.of(box.node).setFocusable(true);
		if (props.disabled != null)
			i.setDisabled(props.disabled);
		if (props.onClick != null)
			i.onClick(props.onClick);
		return box;
	}
}
