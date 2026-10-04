package ashui.components;

import ashui.input.Interaction;
import ashui.layout.Element;
import ashui.reactive.Owner;
import ashui.state.Machine;
import ashui.ui.Component;
import ashui.ui.Text;
import ashui.ui.TopLayer;

typedef TooltipProps = {
	/** What it says. **/
	label:String,
	/** Where it shows: `top` (the default), `bottom`, `left` or `right`, the other side when there is no room. **/
	?side:String,
	/** Seconds the pointer rests on what it holds before it shows; 0.5 by default. **/
	?delay:Float,
	?id:String
}

/**
	A tooltip: a short label shown beside what it holds when the pointer
	rests on it, or when it takes focus from the keyboard, and gone when the
	pointer leaves, a press lands or focus goes. It is drawn in the top layer
	and never takes the pointer. Its states are a `Machine`: closed, waiting
	(the delay running), open, and closing (fading out, then gone). CSS:
	`.ui-tooltip-trigger` (what it holds, `[data-state]` the machine's
	state), `.ui-tooltip`, `[data-side]`, `[closing]` while it fades;
	`--ui-tooltip-bg`, `-fg`, `-radius`.
**/
private enum TipState {
	Closed;
	/** The pointer rests on what it holds; it shows when the delay runs out. **/
	Waiting;
	Open;
	/** Fading out; gone when the top layer takes it away. **/
	Closing;
}

private enum TipEvent {
	Rest;
	Focus;
	Leave;
	Timeout;
	Gone;
}

class Tooltip extends Component<TooltipProps> {
	/** Where it is: closed, waiting, open or closing, a machine of signals; `data-state` on what it holds follows it. **/
	var machine:Machine<TipState, TipEvent>;

	function render():Element {
		machine = new Machine<TipState, TipEvent>(Closed, (s, e) -> switch [s, e] {
			case [Closed, Rest]: Waiting;
			case [Closed, Focus] | [Waiting, Focus] | [Waiting, Timeout]: Open;
			case [Waiting, Leave]: Closed;
			case [Open, Leave]: Closing;
			case [Closing, Gone]: Closed;
			case _: null;
		});
		var trigger = Library.part("ui-tooltip-trigger", null, ["state" => machine.name()], children, props.id);
		var tree = trigger.tree;
		var entry:Null<TopEntry> = null;
		var owner:Null<Owner> = null;
		var theme = ashui.theme.ThemeState.tryGet();
		machine.after(Waiting, props.delay == null ? 0.5 : props.delay, Timeout);
		// The top layer keeps a closing entry this long for its exit animation.
		machine.after(Closing, theme == null ? 0 : theme.animations().durationFaster / 1000, Gone);
		machine.onEnter(Open, _ -> {
			var b = tree.getBounds(trigger.node);
			if (b == null || tree.root == null)
				return;
			// Made under an owner of its own, gone once it has faded out.
			owner = new Owner(tree, @:privateAccess this.owner);
			var tip = owner.run(() -> Library.part("ui-tooltip", null, null, [new Text(props.label, {wrap: false})]));
			entry = TopLayer.open(tree, tip, Beside(b.x, b.y, b.width, b.height, props.side == null ? "top" : props.side, 6), null, null, true);
		});
		machine.onEnter(Closing, _ -> if (entry != null) entry.close());
		machine.onEnter(Closed, _ -> {
			entry = null;
			if (owner != null)
				owner.dispose();
			owner = null;
		});
		var i = Interaction.of(trigger.node);
		i.onPointerEnter(_ -> machine.send(Rest));
		i.onPointerLeave(_ -> machine.send(Leave));
		i.onPointerDown(_ -> machine.send(Leave));
		i.onFocus(_ -> if (i.focusVisible.get()) machine.send(Focus));
		i.onBlur(_ -> machine.send(Leave));
		Owner.onCleanup(() -> {
			if (entry != null)
				entry.close();
			if (owner != null)
				owner.dispose();
		});
		return trigger;
	}
}
