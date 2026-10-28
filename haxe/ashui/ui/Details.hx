package ashui.ui;

import ashui.input.Interaction;
import ashui.layout.Element;
import ashui.layout.IntoReactive;
import ashui.reactive.Signal;
import ashui.reactive.Watch;

typedef DetailsProps = {
	/** Whether the details are expanded. A supplied signal is updated when the summary is toggled. **/
	?open:IntoReactive<Bool>,

	/** Runs after the summary is toggled, with the new open state. **/
	?onToggle:Bool->Void
}

/**
	An expandable section, written as `<details>` in HXX.

	The `<summary>` remains visible. Click it, or press Enter or Space while
	focused, to toggle the content. The `[open]` attribute controls the content
	and marker styles. A missing summary defaults to "Details".
**/
class Details extends Component<DetailsProps> {
	/** Current open state. Uses the supplied signal when available. **/
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
