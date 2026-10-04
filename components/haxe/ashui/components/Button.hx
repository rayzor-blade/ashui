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
	/** Square, for an icon alone. **/
	var Icon = "icon";
}

typedef ButtonProps = {
	?variant:ButtonVariant,
	?size:ButtonSize,
	?disabled:IntoReactive<Bool>,
	/** HTML's button type in a form: `submit` (the default), `reset` or `button`. **/
	?type:String,
	?onClick:PointerEvent->Void,
	?id:String
}

/**
	A button, of a variant and a size: the built-in `<button>`, so it takes
	focus, is clicked by Enter and Space, and submits a form it is in, with
	the library's look. CSS: `.ui-button`, `[data-variant]` (primary,
	secondary, destructive, outline, ghost, link), `[data-size]` (sm, md,
	lg, icon); `--ui-button-bg`, `-bg-hover`, `-bg-active`, `-fg`,
	`-border`, `-height`, `-padding`, `-radius`, `-gap`, `-font-size`.
**/
class Button extends Component<ButtonProps> {
	function render():Element {
		var box = Library.part("ui-button", "button", [
			"variant" => (props.variant == null ? Primary : props.variant : String),
			"size" => (props.size == null ? Md : props.size : String)
		], children, props.id);
		if (props.type != null)
			ashui.css.Identity.of(box.tree, box.node.id).setAttribute("type", props.type);
		var i = Interaction.of(box.node).setFocusable(true);
		if (props.disabled != null)
			i.setDisabled(props.disabled);
		if (props.onClick != null)
			i.onClick(props.onClick);
		return box;
	}
}
