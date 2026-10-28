package ashui.components;

import ashui.input.Interaction;
import ashui.layout.Element;
import ashui.layout.IntoReactive;
import ashui.reactive.Computed;
import ashui.reactive.Signal;
import ashui.reactive.Watch;
import ashui.ui.Component;

typedef ToggleSwitchProps = {
	/** Checked state. A supplied signal is read and updated; a constant sets the initial state. **/
	?checked:IntoReactive<Bool>,
	?disabled:IntoReactive<Bool>,
	/** Receives the new checked state after click, Enter, or Space activation. **/
	?onChange:Bool->Void,
	?size:Size,
	?id:String
}

/**
	An on/off switch with an animated thumb.

	Use `<toggle-switch>` in HXX. Children appear inside the thumb; inline
	SVGs are centered and sized to fit. Apply `ui-switch-icon-off` and
	`ui-switch-icon-on` to two SVGs to crossfade and rotate them without
	rebuilding either icon (26f6deb). Click, Enter, or Space toggles the switch.

	CSS: `.ui-switch` with `:checked`, `:hover`, `:disabled`, `[data-state]`
	(on or off), and `[data-size]`, plus `.ui-switch-thumb`. Variables:
	`--ui-switch-width`, `-height`, `-thumb`, `-travel`, `-track`,
	`-track-hover`, `-track-on`, `-track-on-hover`, `-thumb-bg`, `-icon-size`,
	and `-icon-color`.
**/
class ToggleSwitch extends Component<ToggleSwitchProps> {
	/** Current checked state. Uses the supplied signal when available. **/
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
		// Decorative knob content shares the switch's hit target and focus (26f6deb).
		var thumb = Library.part("ui-switch-thumb", null, null, children);
		ashui.css.Identity.of(thumb.tree, thumb.node.id).setAttribute("aria-hidden", "true");
		var box = Library.part("ui-switch", null, [
			"state" => Computed.make(() -> (on.get() ? "on" : "off" : Null<String>)),
			"size" => (props.size == null ? Size.Md : props.size : String)
		], [thumb], props.id);
		var i = Interaction.of(box.node).setFocusable(true);
		if (props.disabled != null)
			i.setDisabled(props.disabled);
		// CSS's :checked follows the state.
		i.setChecked(on.get());
		new Watch(() -> on.get(), v -> i.setChecked(v));
		i.onClick(_ -> {
			state.set(!state.get());
			if (props.onChange != null)
				props.onChange(state.get());
		});
		return box;
	}
}
