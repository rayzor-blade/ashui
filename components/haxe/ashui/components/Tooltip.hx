package ashui.components;

import ashui.animation.AnimationScheduler;
import ashui.input.Interaction;
import ashui.layout.Element;
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
	and never takes the pointer. CSS: `.ui-tooltip-trigger` (what it holds),
	`.ui-tooltip`, `[data-side]`, `[closing]` while it goes; `--ui-tooltip-bg`,
	`-fg`, `-radius`.
**/
class Tooltip extends Component<TooltipProps> {
	var entry:Null<TopEntry> = null;
	var timer:Null<ashui.animation.AnimationScheduler.Timer> = null;

	function render():Element {
		var trigger = Library.part("ui-tooltip-trigger", null, null, children, props.id);
		var tree = trigger.tree;
		var i = Interaction.of(trigger.node);
		function hide() {
			if (timer != null)
				timer.cancel();
			timer = null;
			if (entry != null)
				entry.close();
			entry = null;
		}
		function show() {
			timer = null;
			if (entry != null)
				return;
			var b = tree.getBounds(trigger.node);
			if (b == null || tree.root == null)
				return;
			// Made under an owner of its own, gone with it when the tooltip closes.
			var owner = new ashui.reactive.Owner(tree, @:privateAccess this.owner);
			var tip = owner.run(() -> Library.part("ui-tooltip", null, null, [new Text(props.label, {wrap: false})]));
			entry = TopLayer.open(tree, tip, Beside(b.x, b.y, b.width, b.height, props.side == null ? "top" : props.side, 6), null, () -> {
				entry = null;
				owner.dispose();
			}, true);
		}
		i.onPointerEnter(_ -> {
			if (timer == null && entry == null)
				timer = AnimationScheduler.main.after(props.delay == null ? 0.5 : props.delay, show);
		});
		i.onPointerLeave(_ -> hide());
		i.onPointerDown(_ -> hide());
		i.onFocus(_ -> if (i.focusVisible.get()) show());
		i.onBlur(_ -> hide());
		ashui.reactive.Owner.onCleanup(hide);
		return trigger;
	}
}
