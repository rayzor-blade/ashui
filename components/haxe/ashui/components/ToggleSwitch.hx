package ashui.components;

import ashui.input.Interaction;
import ashui.layout.Element;
import ashui.layout.IntoReactive;
import ashui.reactive.Computed;
import ashui.reactive.Signal;
import ashui.reactive.Watch;
import ashui.ui.Component;

typedef ToggleSwitchProps = {
	/** Whether it is on. A signal is read and written, so the switch and your code share it; a constant sets it once. **/
	?checked:IntoReactive<Bool>,
	?disabled:IntoReactive<Bool>,
	/** Called with whether it is on, after a click, Enter or Space turns it. **/
	?onChange:Bool->Void,
	?size:Size,
	?id:String
}

/**
	An on and off switch: a track and its `thumb`, which slides across when
	it is on. It takes focus, and a click, Enter or Space turns it. In hxx
	it is `<toggle-switch>`: `switch` is a Haxe keyword hxx keeps. CSS:
	`.ui-switch`, `:checked`, `:hover`, `:disabled`, `[data-state]` (on,
	off), `[data-size]`, `.ui-switch-thumb`; `--ui-switch-width`, `-height`, `-thumb`,
	`-travel`, `-track`, `-track-hover`, `-track-on`, `-track-on-hover`,
	`-thumb-bg`.
**/
class ToggleSwitch extends Component<ToggleSwitchProps> {
	/** Whether it is on; the caller's signal when `checked` was one. **/
	public var state(default, null):Signal<Bool>;

	function render():Element {
		state = switch props.checked {
			case null: Signal.make(false);
			case Const(v): Signal.make(v);
			case Bound(s): s;
			case Derived(c):
				var s = Signal.make(c.get());
				new Watch(() -> c.get(), v -> s.set(v));
				s;
		}
		var on = state;
		var thumb = Library.part("ui-switch-thumb");
		var box = Library.part("ui-switch", null, [
			"state" => Computed.make(() -> (on.get() ? "on" : "off" : Null<String>)),
			"size" => (props.size == null ? Size.Md : props.size : String)
		], [thumb], props.id);
		var i = Interaction.of(box.node).setFocusable(true);
		if (props.disabled != null)
			i.setDisabled(props.disabled);
		// CSS's :checked follows the state.
		i.checked.set(on.get());
		new Watch(() -> on.get(), v -> i.checked.set(v));
		i.onClick(_ -> {
			state.set(!state.get());
			if (props.onChange != null)
				props.onChange(state.get());
		});
		return box;
	}
}
