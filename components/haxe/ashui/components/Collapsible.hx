package ashui.components;

import ashui.input.Interaction;
import ashui.layout.Element;
import ashui.layout.IntoReactive;
import ashui.reactive.Computed;
import ashui.reactive.Signal;
import ashui.reactive.Watch;
import ashui.ui.Component;

typedef CollapsibleProps = {
	/** Whether it is open. A signal is read and written; a constant sets it once. **/
	?open:IntoReactive<Bool>,
	?onOpenChange:Bool->Void,
	?disabled:Bool,
	?id:String
}

/**
	A panel that opens and closes: a `CollapsibleTrigger` and a
	`CollapsibleContent`, which grows open and shrinks shut by layout
	animation, its content revealed rather than stretched. CSS:
	`.ui-collapsible`, `.ui-collapsible-trigger`, `.ui-collapsible-content`,
	each `[data-state]` open or closed (closed content is laid out at no
	height).
**/
class Collapsible extends Component<CollapsibleProps> {
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

/** What opens and closes a collapsible: clicked, or Enter or Space while it has focus. **/
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

/** What a collapsible shows while open, growing in and shrinking out by layout animation. **/
class CollapsibleContent extends Component<{?id:String}> {
	/** The collapsible's state, set by it. **/
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
