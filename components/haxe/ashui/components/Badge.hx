package ashui.components;

import ashui.ui.Component;
import ashui.layout.Element;

enum abstract BadgeVariant(String) to String {
	var Primary = "primary";
	var Secondary = "secondary";
	var Destructive = "destructive";
	var Success = "success";
	var Warning = "warning";
}

/** How a badge wears its colour: a tint of it (the default), filled with it, or edged with it. **/
enum abstract BadgeAppearance(String) to String {
	var Soft = "soft";
	var Solid = "solid";
	var Outline = "outline";
}

typedef BadgeProps = {
	?variant:BadgeVariant,
	?appearance:BadgeAppearance,
	?id:String
}

/** A small label: a count, a status. CSS: `.ui-badge`, `[data-variant]`, `[data-appearance]`; `--ui-badge-bg`, `-fg`, `-border`, `-padding`, `-radius`, `-font-size`. **/
class Badge extends Component<BadgeProps> {
	function render():Element
		return Library.part("ui-badge", null, [
			"variant" => (props.variant == null ? Primary : props.variant : String),
			"appearance" => (props.appearance == null ? Soft : props.appearance : String)
		], children, props.id);
}
