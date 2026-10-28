package ashui.components;

import ashui.ui.Component;
import ashui.layout.Element;

enum abstract AlertVariant(String) to String {
	var Default = "default";
	var Destructive = "destructive";
	var Success = "success";
	var Warning = "warning";
	var Info = "info";
}

typedef AlertProps = {
	?variant:AlertVariant,
	?id:String
}

/**
	A callout with a title, description, and optional leading SVG icon.
	The icon occupies a separate column when supplied as the first child.

	CSS: `.ui-alert`, `[data-variant]` (default, destructive, success, warning,
	info), `.ui-alert-title`, `.ui-alert-description`. Variables:
	`--ui-alert-bg`, `-fg`, `-border`, `-icon`, `-padding`, and `-radius`.
**/
class Alert extends Component<AlertProps> {
	function render():Element
		return Library.part("ui-alert", null, ["variant" => (props.variant == null ? Default : props.variant : String)], children, props.id);
}

/** Title text for an alert. **/
class AlertTitle extends Component<{?id:String}> {
	function render():Element {
		var box = Library.part("ui-alert-title", null, null, children, props.id);
		ashui.text.InlineFlow.attach(box);
		return box;
	}
}

/** Supporting text for an alert. **/
class AlertDescription extends Component<{?id:String}> {
	function render():Element {
		var box = Library.part("ui-alert-description", null, null, children, props.id);
		ashui.text.InlineFlow.attach(box);
		return box;
	}
}
