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

/** Badge color treatment: tinted (default), solid, or outlined. **/
enum abstract BadgeAppearance(String) to String {
	var Soft = "soft";
	var Solid = "solid";
	var Outline = "outline";
}

typedef BadgeProps = {
	?variant:BadgeVariant,
	?appearance:BadgeAppearance,
	/** Small, medium (default), or large text and padding (e8a1b50). **/
	?size:Size,
	?id:String
}

/**
	A compact status or count label.
	CSS: `.ui-badge`, `[data-variant]`, `[data-appearance]`. Variables:
	`--ui-badge-bg`, `-fg`, `-border`, `-padding`, `-radius`, and `-font-size`.
**/
class Badge extends Component<BadgeProps> {
	function render():Element
		return Library.part("ui-badge", null, [
			"size" => (props.size == null ? Size.Md : props.size : String),
			"variant" => (props.variant == null ? Primary : props.variant : String),
			"appearance" => (props.appearance == null ? Soft : props.appearance : String)
		], children, props.id);
}
