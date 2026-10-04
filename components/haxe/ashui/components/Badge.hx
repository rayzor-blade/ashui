package ashui.components;

import ashui.ui.Component;
import ashui.layout.Element;

enum abstract BadgeVariant(String) to String {
	var Primary = "primary";
	var Secondary = "secondary";
	var Destructive = "destructive";
	var Success = "success";
	var Warning = "warning";
	var Outline = "outline";
}

typedef BadgeProps = {
	?variant:BadgeVariant,
	?id:String
}

/** A small label: a count, a status. CSS: `.ui-badge`, `[data-variant]`; `--ui-badge-bg`, `-fg`, `-border`, `-padding`, `-radius`, `-font-size`. **/
class Badge extends Component<BadgeProps> {
	function render():Element
		return Library.part("ui-badge", null, ["variant" => (props.variant == null ? Primary : props.variant : String)], children, props.id);
}
