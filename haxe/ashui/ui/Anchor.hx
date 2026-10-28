package ashui.ui;

import ashui.input.Events;
import ashui.input.Interaction;
import ashui.layout.Element;

typedef AnchorProps = {
	/** URL to open with the system handler when the link is activated. `onClick` can prevent navigation. **/
	?href:String,

	/** Runs before navigation. Call `preventDefault()` to keep the URL from opening. **/
	?onClick:PointerEvent->Void,

	?id:String
}

/**
	A link, written as `<a>` in HXX.

	Activate the link with a click or Enter. Activation calls `onClick`, then
	opens `href` with the system handler unless the event was prevented.
	Only links with an `href` receive focus. The user-agent stylesheet supplies
	the `a`, `:hover`, and `:focus-visible` styles.
**/
class Anchor extends Component<AnchorProps> {
	function render():Element {
		var box = new Div({tag: "a", id: props.id}, children);
		var identity = ashui.css.Identity.of(box.tree, box.node.id);
		if (props.href != null)
			identity.setAttribute("href", props.href);
		var interaction = Interaction.of(box.node).setFocusable(props.href != null);
		interaction.onClick(e -> {
			if (props.onClick != null)
				props.onClick(e);
			if (props.href != null && !e.defaultPrevented)
				open(props.href);
		});
		return box;
	}

	/** Opens a URL with the system handler, such as the default web browser. **/
	public static function open(url:String):Void {
		#if wasm
		// A page starts no process, and xwindow has no command to ask it to open a link.
		return;
		#end
		var command = switch Sys.systemName() {
			case "Mac": "open";
			case "Windows": "explorer";
			case _: "xdg-open";
		}
		// Started, not waited for: the browser may outlive the app.
		new sys.io.Process(command, [url]);
	}
}
