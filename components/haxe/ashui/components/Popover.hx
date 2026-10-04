package ashui.components;

import ashui.components.Button;
import ashui.layout.Element;
import ashui.layout.IntoReactive;
import ashui.reactive.Computed;
import ashui.reactive.Signal;
import ashui.reactive.Watch;
import ashui.ui.Component;
import ashui.ui.Div;

typedef PopoverProps = {
	/** Whether it is open. A signal is read and written; a constant sets it once. **/
	?open:IntoReactive<Bool>,
	/** Which side of its trigger it opens on: "bottom" (the default), "top", "left" or "right"; the other side when there is no room. **/
	?side:String,
	?onOpenChange:Bool->Void,
	?id:String
}

/**
	A popover: a `PopoverTrigger` that opens and closes it, and a
	`PopoverContent` shown beside the trigger in the top layer, rising into
	place. A press outside it or Escape closes it. CSS:
	`.ui-popover-root` (`[data-state]`), `.ui-popover` (the panel,
	`[data-side]`, `[closing]`); `--ui-popover-bg`, `-border`, `-radius`,
	`-padding`, `-shadow`, `-width`.
**/
class Popover extends Component<PopoverProps> {
	/** Whether it is open; the caller's signal when `open` was one. **/
	public var opened(default, null):Signal<Bool>;

	@:allow(ashui.components)
	static final registry = new Registry<Popover>();

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
		if (props.onOpenChange != null) {
			var first = true;
			new Watch(() -> open.get(), v -> if (first) first = false else props.onOpenChange(v));
		}
		var root = Library.part("ui-popover-root", null, ["state" => Computed.make(() -> (open.get() ? "open" : "closed" : Null<String>))], children,
			props.id);
		registry.add(root.tree, root.node.id, this);
		var trigger:Null<Element> = null, content:Null<PopoverContent> = null;
		for (c in children)
			if (Std.isOfType(c, PopoverTrigger))
				trigger = c;
			else if (Std.isOfType(c, PopoverContent))
				content = cast c;
		if (content != null) {
			registry.add(content.panel.tree, content.panel.node.id, this);
			// Its own state, so its opening animation plays as it opens, not when it is first styled out of sight.
			ashui.css.Identity.of(content.panel.tree, content.panel.node.id)
				.bindAttribute("data-state", Computed.make(() -> (open.get() ? "open" : "closed" : Null<String>)));
			var floating = new Floating(opened, content.panel);
			if (trigger != null)
				floating.anchorTo(trigger, props.side == null ? "bottom" : props.side, 4);
		}
		return root;
	}
}

/** A button that opens and closes the popover it is in; it takes a Button's `variant` and `size`. **/
class PopoverTrigger extends Component<{?variant:ButtonVariant, ?size:ButtonSize, ?id:String}> {
	function render():Element {
		var button:Null<Button> = null;
		button = new Button({
			variant: props.variant == null ? Outline : props.variant,
			size: props.size,
			type: "button",
			id: props.id,
			onClick: _ -> {
				var p = Popover.registry.near(button.tree, button.node.id);
				if (p != null)
					p.opened.set(!p.opened.get());
			}
		}, children);
		return button;
	}
}

/** What a popover shows: kept while it is closed, in the top layer while it is open. **/
class PopoverContent extends Component<{?id:String}> {
	@:allow(ashui.components.Popover)
	var panel(default, null):Div;

	function render():Element {
		panel = Library.part("ui-popover", null, null, children, props.id);
		// The panel itself goes to the top layer; this placeholder keeps its place among its siblings.
		var holder = new Div({});
		holder.node.set(ashui.layout.Prop.Display, ashui.types.Style.Display.None);
		return holder;
	}
}
