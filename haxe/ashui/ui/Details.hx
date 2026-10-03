package ashui.ui;

import ashui.input.Interaction;
import ashui.layout.Element;
import ashui.layout.IntoReactive;
import ashui.reactive.Signal;
import ashui.reactive.Watch;

typedef DetailsProps = {
	/** Whether it is open. A signal is read and written: toggling it sets it. **/
	?open:IntoReactive<Bool>,

	/** Called with whether it is open, after its summary toggles it. **/
	?onToggle:Bool->Void
}

/**
	HTML's `<details>`, built in: its `<summary>` shows always, and a click,
	Enter or Space on the summary shows or hides the rest. It is marked
	`[open]` while open, which the user-agent stylesheet reads to hide its
	content and turn the summary's marker. Without a summary, it shows
	"Details", as HTML's does.
**/
class Details extends Component<DetailsProps> {
	/** Whether it is open; the caller's signal when `open` was one. **/
	public var opened(default, null):Signal<Bool>;

	function render():Element {
		opened = switch props.open {
			case null: Signal.make(false);
			case Const(v): Signal.make(v);
			case Bound(s): s;
			case Derived(c):
				var s = Signal.make(c.get());
				new Watch(() -> c.get(), v -> s.set(v));
				s;
		}
		var summary:Null<Element> = Lambda.find(children, c -> Std.isOfType(c, Summary));
		if (summary == null)
			summary = new Summary({}, [new Text("Details")]);
		var rest = children.filter(c -> c != summary);
		var content = new Div({classes: ["content"]}, rest);
		var box = new Div({tag: "details"}, [summary, content]);
		var identity = ashui.css.Identity.of(box.tree, box.node.id);
		new Watch(() -> opened.get(), v -> identity.setAttribute("open", v ? "" : null));
		Interaction.of(summary.node).onClick(_ -> {
			opened.set(!opened.get());
			if (props.onToggle != null)
				props.onToggle(opened.get());
		});
		return box;
	}
}
