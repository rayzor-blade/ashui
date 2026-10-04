package ashui.components;

import ashui.input.Interaction;
import ashui.layout.Element;
import ashui.reactive.Signal;
import ashui.state.Machine;
import ashui.ui.Component;
import ashui.ui.Div;

typedef HoverCardProps = {
	/** Which side of its trigger it opens on: "bottom" (the default), "top", "left" or "right". **/
	?side:String,
	/** Seconds the pointer rests on the trigger before it opens; 0.5 by default. **/
	?openDelay:Float,
	/** Seconds after the pointer leaves before it closes, so it can cross to the card; 0.3 by default. **/
	?closeDelay:Float,
	?id:String
}

/** Where a hover card is: closed, waiting to open, open, or waiting to close. **/
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
	A card of detail shown while the pointer rests on its `HoverCardTrigger`,
	a profile behind a name: it opens after a delay, beside the trigger, and
	stays while the pointer is on the trigger or on the card, so the card can
	be read and its links followed. It takes no backdrop: the page beneath
	stays under the pointer. Its life is a `Machine`; `data-state` on the
	trigger is closed, waiting, open or leaving. CSS:
	`.ui-hover-card-trigger` (`[data-state]`), `.ui-hover-card` (the card,
	`[data-side]`, `[data-state]`, `[closing]`).
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

/** What the pointer rests on to open the card; its children are the trigger, a name or an avatar. **/
class HoverCardTrigger extends Component<{?id:String}> {
	function render():Element {
		var box = Library.part("ui-hover-card-trigger", null, null, children, props.id);
		Interaction.of(box.node).setFocusable(true);
		return box;
	}
}

/** The card: kept while closed, in the top layer while open. **/
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
