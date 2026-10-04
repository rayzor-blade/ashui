package ashui.components;

import ashui.input.Focus;
import ashui.input.Interaction;
import ashui.layout.Element;
import ashui.layout.IntoReactive;
import ashui.reactive.Computed;
import ashui.reactive.Signal;
import ashui.reactive.Watch;
import ashui.ui.Component;

enum abstract ToggleVariant(String) to String {
	/** No edge; a faint fill while on. **/
	var Default = "default";
	/** A hairline edge, on or off. **/
	var Outline = "outline";
}

typedef ToggleProps = {
	/** Whether it is on. A signal is read and written; a constant sets it once. **/
	?pressed:IntoReactive<Bool>,
	?variant:ToggleVariant,
	?size:Size,
	?disabled:IntoReactive<Bool>,
	/** Called with whether it is on after a press turns it. **/
	?onChange:Bool->Void,
	?id:String
}

/**
	A button that stays pressed: bold in a toolbar, a filter. Its children are
	its label or icon. A press, Enter or Space turns it. CSS: `.ui-toggle`
	(`[data-state]` on or off, `[data-variant]`, `[data-size]`, `:hover`,
	`:active`, `:disabled`).
**/
class Toggle extends Component<ToggleProps> {
	public var pressed(default, null):Signal<Bool>;

	function render():Element {
		pressed = switch props.pressed {
			case null: Signal.make(false);
			case Const(v): Signal.make(v);
			case Bound(s): s;
			case Derived(c):
				var s = Signal.make(c.get());
				new Watch(() -> c.get(), v -> s.set(v));
				s;
		}
		var on = pressed;
		var box = Library.part("ui-toggle", "button", [
			"state" => Computed.make(() -> (on.get() ? "on" : "off" : Null<String>)),
			"variant" => (props.variant == null ? ToggleVariant.Default : props.variant : String),
			"size" => (props.size == null ? Size.Md : props.size : String)
		], children, props.id);
		ashui.css.Identity.of(box.tree, box.node.id).setAttribute("type", "button");
		var i = Interaction.of(box.node).setFocusable(true);
		if (props.disabled != null)
			i.setDisabled(props.disabled);
		i.onClick(_ -> {
			on.set(!on.get());
			if (props.onChange != null)
				props.onChange(on.get());
		});
		return box;
	}
}

typedef ToggleGroupProps = {
	/** "single" (the default), one on at a time, or "multiple". **/
	?type:String,
	/** The values of the items on. A signal is read and written. **/
	?value:IntoReactive<Array<String>>,
	/** Whether the item on in a single group can be turned off, leaving none; false by default. **/
	?deselectable:Bool,
	?variant:ToggleVariant,
	?size:Size,
	?disabled:IntoReactive<Bool>,
	?onValueChange:Array<String>->Void,
	?id:String
}

/**
	Toggles that act as one: `ToggleGroupItem`s, each with a `value`, one
	on at a time or several; the arrows, Home and End move among them.
	Text alignment in an editor's toolbar. CSS: `.ui-toggle-group`
	(`[data-variant]`, `[data-size]`), its items `.ui-toggle`.
**/
class ToggleGroup extends Component<ToggleGroupProps> {
	public var value(default, null):Signal<Array<String>>;

	function render():Element {
		value = switch props.value {
			case null: Signal.make(([] : Array<String>));
			case Const(v): Signal.make(v);
			case Bound(s): s;
			case Derived(c):
				var s = Signal.make(c.get());
				new Watch(() -> c.get(), v -> s.set(v));
				s;
		}
		var v = value;
		var multiple = props.type == "multiple";
		var items = [for (c in children) if (Std.isOfType(c, ToggleGroupItem)) (cast c : ToggleGroupItem)];
		for (item in items) {
			var it = item;
			it.bindTo(v, () -> {
				var now = v.get();
				var on = now.indexOf(it.props.value) >= 0;
				var next = multiple ? (on ? now.filter(x -> x != it.props.value) : now.concat([it.props.value])) : (on ? (props.deselectable == true ? [] : now) : [it.props.value]);
				if (next.join("\u0000") != now.join("\u0000")) {
					v.set(next);
					if (props.onValueChange != null)
						props.onValueChange(next);
				}
			}, props.disabled);
		}
		var box = Library.part("ui-toggle-group", null, [
			"variant" => (props.variant == null ? ToggleVariant.Default : props.variant : String),
			"size" => (props.size == null ? Size.Md : props.size : String)
		], children, props.id);
		// The arrows move among the enabled items.
		Interaction.of(box.node).onKeyDown(e -> {
			var enabled = items.filter(x -> !x.interaction.disabled.get());
			var at = Lambda.findIndex(enabled, x -> x.interaction.focused.get());
			if (enabled.length == 0 || at < 0)
				return;
			var next = switch e.key {
				case Named(ArrowRight) | Named(ArrowDown): (at + 1) % enabled.length;
				case Named(ArrowLeft) | Named(ArrowUp): (at - 1 + enabled.length) % enabled.length;
				case Named(Home): 0;
				case Named(End): enabled.length - 1;
				case _: -1;
			}
			if (next < 0)
				return;
			e.preventDefault();
			Focus.set(enabled[next].interaction, true);
		});
		return box;
	}
}

/** One of a toggle group's items; its children are its label or icon. **/
class ToggleGroupItem extends Component<{value:String, ?disabled:IntoReactive<Bool>, ?id:String}> {
	@:allow(ashui.components.ToggleGroup) var interaction(default, null):Interaction;
	final group = Signal.make((null : Null<Signal<Array<String>>>));
	var press:Null<Void->Void> = null;

	function render():Element {
		var g = group, value = props.value;
		var box = Library.part("ui-toggle", "button", [
			"state" => Computed.make(() -> {
				var s = g.get();
				(s != null && s.get().indexOf(value) >= 0 ? "on" : "off" : Null<String>);
			})
		], children, props.id);
		ashui.css.Identity.of(box.tree, box.node.id).setAttribute("type", "button");
		interaction = Interaction.of(box.node).setFocusable(true);
		if (props.disabled != null)
			interaction.setDisabled(props.disabled);
		interaction.onClick(_ -> if (press != null) press());
		return box;
	}

	@:allow(ashui.components.ToggleGroup)
	function bindTo(value:Signal<Array<String>>, onPress:Void->Void, disabled:Null<IntoReactive<Bool>>):Void {
		group.set(value);
		press = onPress;
		if (props.disabled == null && disabled != null)
			interaction.setDisabled(disabled);
	}
}
