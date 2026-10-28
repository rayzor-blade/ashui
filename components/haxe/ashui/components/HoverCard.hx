package ashui.components;

import ashui.input.Interaction;
import ashui.layout.Element;
import ashui.reactive.Signal;
import ashui.state.Machine;
import ashui.ui.Component;
import ashui.ui.Div;

typedef HoverCardProps = {
	/** Side of the trigger: `bottom` (default), `top`, `left`, or `right`. **/
	?side:String,
	/** Hover delay before opening, in seconds. Defaults to 0.5. **/
	?openDelay:Float,
	/** Delay before closing after the pointer leaves, allowing movement into the card. Defaults to 0.3 seconds. **/
	?closeDelay:Float,
	?id:String
}

/** Hover-card lifecycle: closed, waiting to open, open, or waiting to close. **/
private enum CardState {
	Closed;
	Waiting;
	Open;
	Leaving;
}

private enum CardEvent {
	Enter;
	Leave;
	Timeout;
}

/**
	A detail card displayed after hovering over `HoverCardTrigger`.
	The card remains open while the pointer is over the trigger or the card,
	so its content and links remain usable. It has no backdrop and leaves
	the page interactive. An FSM manages opening and closing delays.

	CSS: `.ui-hover-card-trigger[data-state]` and `.ui-hover-card` with
	`[data-side]`, `[data-state]`, and `[closing]`. Trigger states are
	`closed`, `waiting`, `open`, and `leaving`.
**/
class HoverCard extends Component<HoverCardProps> {
	function render():Element {
		var machine = new Machine<CardState, CardEvent>(Closed, (s, e) -> switch [s, e] {
			case [Closed, Enter]: Waiting;
			case [Waiting, Leave]: Closed;
			case [Waiting, Timeout]: Open;
			case [Open, Leave]: Leaving;
			case [Leaving, Enter]: Open;
			case [Leaving, Timeout]: Closed;
			case _: null;
		});
		machine.after(Waiting, props.openDelay == null ? 0.5 : props.openDelay, Timeout);
		machine.after(Leaving, props.closeDelay == null ? 0.3 : props.closeDelay, Timeout);
		var open = Signal.make(false);
		machine.onEnter(Open, _ -> open.set(true));
		machine.onEnter(Closed, _ -> open.set(false));

		var trigger:Null<HoverCardTrigger> = null, content:Null<HoverCardContent> = null;
		for (c in children)
			if (Std.isOfType(c, HoverCardTrigger))
				trigger = cast c;
			else if (Std.isOfType(c, HoverCardContent))
				content = cast c;
		var root = Library.part("ui-hover-card-root", null, null, children, props.id);
		if (trigger != null) {
			ashui.css.Identity.of(trigger.tree, trigger.node.id).bindAttribute("data-state", machine.name());
			var ti = Interaction.of(trigger.node);
			ti.onPointerEnter(_ -> machine.send(Enter));
			ti.onPointerLeave(_ -> machine.send(Leave));
			ti.onFocus(_ -> if (ti.focusVisible.get()) machine.send(Enter));
			ti.onBlur(_ -> machine.send(Leave));
		}
		if (content != null) {
			var panel = content.panel;
			ashui.css.Identity.of(panel.tree, panel.node.id).bindAttribute("data-state", machine.name());
			var ci = Interaction.of(panel.node);
			ci.onPointerEnter(_ -> machine.send(Enter));
			ci.onPointerLeave(_ -> machine.send(Leave));
			var floating = new Floating(open, panel);
			floating.modeless = true;
			if (trigger != null)
				floating.anchorTo(trigger, props.side == null ? "bottom" : props.side, 8);
		}
		return root;
	}
}

/** Hover target that opens the card. Children can be a name, avatar, or other content. **/
class HoverCardTrigger extends Component<{?id:String}> {
	function render():Element {
		var box = Library.part("ui-hover-card-trigger", null, null, children, props.id);
		Interaction.of(box.node).setFocusable(true);
		return box;
	}
}

/** Hover-card panel, retained while closed and moved to the top layer while open. **/
class HoverCardContent extends Component<{?id:String}> {
	@:allow(ashui.components.HoverCard)
	var panel(default, null):Div;

	function render():Element {
		panel = Library.part("ui-hover-card", null, null, children, props.id);
		var holder = new Div({});
		holder.node.set(ashui.layout.Prop.Display, ashui.types.Style.Display.None);
		return holder;
	}
}
