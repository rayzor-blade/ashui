package ashui.components;

import ashui.input.Interaction;
import ashui.layout.Element;
import ashui.layout.IntoReactive;
import ashui.reactive.Computed;
import ashui.reactive.Signal;
import ashui.reactive.Watch;
import ashui.ui.Component;

typedef CollapsibleProps = {
	/** Whether the panel is open. A supplied signal is read and updated; a constant sets the initial state. **/
	?open:IntoReactive<Bool>,
	?onOpenChange:Bool->Void,
	?disabled:Bool,
	?id:String
}

/**
	An expandable panel controlled by a `CollapsibleTrigger`.
	`CollapsibleContent` animates its height while revealing the content
	without stretching it. Closed content has zero height. CSS parts:
	`.ui-collapsible`, `.ui-collapsible-trigger`, and `.ui-collapsible-content`,
	each with `[data-state="open"]` or `[data-state="closed"]`.
**/
class Collapsible extends Component<CollapsibleProps> {
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
		var open = opened;
		var state = Computed.make(() -> (open.get() ? "open" : "closed" : Null<String>));
		for (c in children)
			if (Std.isOfType(c, CollapsibleTrigger))
				(cast c : CollapsibleTrigger).bind(state, () -> {
					if (props.disabled == true)
						return;
					open.set(!open.get());
					if (props.onOpenChange != null)
						props.onOpenChange(open.get());
				});
			else if (Std.isOfType(c, CollapsibleContent))
				(cast c : CollapsibleContent).state.set(state);
		return Library.part("ui-collapsible", null, ["state" => state], children, props.id);
	}
}

/** Toggles a collapsible panel on click, Enter, or Space. **/
class CollapsibleTrigger extends Component<{?id:String}> {
	final state = Signal.make((null : Null<Computed<Null<String>>>));
	var toggle:Null<Void->Void> = null;

	function render():Element {
		var s = state;
		var box = Library.part("ui-collapsible-trigger", "button", ["state" => Computed.make(() -> {
			var c = s.get();
			(c == null ? "closed" : c.get() : Null<String>);
		})], children, props.id);
		ashui.css.Identity.of(box.tree, box.node.id).setAttribute("type", "button");
		Interaction.of(box.node).setFocusable(true).onClick(_ -> if (toggle != null) toggle());
		return box;
	}

	@:allow(ashui.components)
	function bind(s:Computed<Null<String>>, onToggle:Void->Void):Void {
		state.set(s);
		toggle = onToggle;
	}
}

/** Panel content with animated expansion and collapse. **/
class CollapsibleContent extends Component<{?id:String}> {
	/** Open state supplied by the parent collapsible. **/
	@:allow(ashui.components)
	final state = Signal.make((null : Null<Computed<Null<String>>>));

	function render():Element {
		var s = state;
		var box = Library.part("ui-collapsible-content", null, ["state" => Computed.make(() -> {
			var c = s.get();
			(c == null ? "closed" : c.get() : Null<String>);
		})], children, props.id);
		ashui.animation.LayoutAnimation.attach(box.node);
		return box;
	}
}
