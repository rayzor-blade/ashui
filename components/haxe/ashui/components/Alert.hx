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
	A callout: an optional icon (an `<svg>` first), an `AlertTitle` and an
	`AlertDescription`. With an icon, the icon takes a column of its own.
	CSS: `.ui-alert`, `[data-variant]` (default, destructive, success,
	warning, info), `.ui-alert-title`, `.ui-alert-description`;
	`--ui-alert-bg`, `-fg`, `-border`, `-icon`, `-padding`, `-radius`.
**/
class Alert extends Component<AlertProps> {
	function render():Element
		return Library.part("ui-alert", null, ["variant" => (props.variant == null ? Default : props.variant : String)], children, props.id);
}

/** An alert's title, a flow of text. **/
class AlertTitle extends Component<{?id:String}> {
	function render():Element {
		var box = Library.part("ui-alert-title", null, null, children, props.id);
		ashui.text.InlineFlow.attach(box);
		return box;
	}
}

/** An alert's description, a flow of text. **/
class AlertDescription extends Component<{?id:String}> {
	function render():Element {
		var box = Library.part("ui-alert-description", null, null, children, props.id);
		ashui.text.InlineFlow.attach(box);
		return box;
	}
}
