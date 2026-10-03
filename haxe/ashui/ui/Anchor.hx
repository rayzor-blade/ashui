package ashui.ui;

import ashui.input.Events;
import ashui.input.Interaction;
import ashui.layout.Element;

typedef AnchorProps = {
	/** Where it goes: a URL opened in the system's browser when it is followed, unless `onClick` prevents that. **/
	?href:String,

	/** Called when it is followed, before `href` is opened; `preventDefault` keeps `href` from opening. **/
	?onClick:PointerEvent->Void,

	?id:String
}

/**
	HTML's `<a>`, built in as hxx's `<a>`: a link, followed by a click or by
	Enter while it has focus. Following it calls `onClick`, then opens
	`href` with the system's handler for it, a web page in the browser.
	Only an `<a>` with an `href` takes focus, as HTML's. Its look is the
	user-agent stylesheet's `a`, with `:hover` and `:focus-visible`.
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

	/** Opens `url` with the system's handler for it. **/
	public static function open(url:String):Void {
		var command = switch Sys.systemName() {
			case "Mac": "open";
			case "Windows": "explorer";
			case _: "xdg-open";
		}
		// Started, not waited for: the browser may outlive the app.
		new sys.io.Process(command, [url]);
	}
}
