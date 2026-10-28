package ashui.components;

import ashui.input.Interaction;
import ashui.layout.Element;
import ashui.layout.IntoReactive;
import ashui.reactive.Owner;
import ashui.reactive.Watch;
import ashui.state.Machine;
import ashui.ui.Component;
import ashui.ui.Text;
import ashui.ui.TopLayer;

typedef TooltipProps = {
	/** Tooltip text. Accepts reactive values. **/
	label:IntoReactive<String>,
	/** Preferred side: `top` (default), `bottom`, `left`, or `right`. Flips when space is limited. **/
	?side:String,
	/** Hover delay before showing the tooltip, in seconds. Defaults to 0.5. **/
	?delay:Float,
	?id:String
}

/** Tooltip lifecycle states. **/
private enum TipState {
	Closed;
	/** Waiting for the hover delay to expire. **/
	Waiting;
	Open;
	/** Fading out before the top-layer entry is removed. **/
	Closing;
}

private enum TipEvent {
	Rest;
	Focus;
	Leave;
	Timeout;
	Gone;
}

/**
	A short label shown on hover or keyboard focus.
	Wrap the target in a tooltip. The label appears in the top layer after
	the hover delay and closes on pointer leave, press, or focus loss.
	It ignores pointer input. An FSM manages the delay and exit fade.

	CSS: `.ui-tooltip-trigger[data-state]`, `.ui-tooltip`, `[data-side]`,
	and `[closing]`. States are `closed`, `waiting`, `open`, and `closing`.
	Variables: `--ui-tooltip-bg`, `--ui-tooltip-fg`, and `--ui-tooltip-radius`.
**/
class Tooltip extends Component<TooltipProps> {
	/** Lifecycle FSM. Its state is exposed on the trigger through `data-state`. **/
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
			var b = tree.getScrolledBounds(trigger.node);
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
		// 8dd8f7e: focus events target the actual child control; focusWithin
		// and its focusVisible signal keep the existing FSM in sync instead.
		function keyboardFocused():Bool {
			var focused = ashui.input.Focus.of(tree);
			return i.focusWithin.get() && focused != null && focused.focusVisible.get();
		}
		i.onPointerEnter(_ -> machine.send(Rest));
		i.onPointerLeave(_ -> if (!keyboardFocused()) machine.send(Leave));
		i.onPointerDown(_ -> machine.send(Leave));
		new Watch(keyboardFocused, focused -> {
			if (focused) machine.send(Focus);
			else if (!i.hovered.get()) machine.send(Leave);
		});
		Owner.onCleanup(() -> {
			if (entry != null)
				entry.close();
			if (owner != null)
				owner.dispose();
		});
		return trigger;
	}
}
