package ashui.components;

import ashui.layout.Element;
import ashui.layout.IntoReactive;
import ashui.reactive.Computed;
import ashui.reactive.Signal;
import ashui.reactive.Watch;
import ashui.ui.Component;

typedef SliderProps = {
	/** Where it is. A signal is read and written; a constant sets it once. **/
	?value:IntoReactive<Float>,
	?min:Float,
	?max:Float,
	?step:Float,
	/** Horizontal by default; vertical increases from bottom to top. **/
	?orientation:String,
	/** A label over it, its value shown at the other end. **/
	?label:String,
	/** How the value is shown beside the label; to two decimals by default. **/
	?format:Float->String,
	?disabled:IntoReactive<Bool>,
	/** Called on pointer or keyboard edits; changes to the bound value do not call it. **/
	?onChange:Float->Void,
	?name:String,
	?id:String
}

/**
	A slider: the built-in `<input type="range">` (its keys, its drag) in
	the library's look, with a label over it and its value at the label's
	end. CSS: `.ui-slider-field`, `.ui-slider-header`, `.ui-slider-label`,
	`.ui-slider-value`, `.ui-slider` (the range, its `.fill`, `.rest`,
	`.thumb`, `:disabled`).
	Children decorate the range itself; position an icon absolutely so it
	does not take space from the track. A press on it still seeks the range.
**/
class Slider extends Component<SliderProps> {
	public var value(default, null):Signal<Float>;

	function render():Element {
		Library.use();
		value = switch props.value {
			case null: Signal.make(props.min == null ? 0.0 : props.min);
			case Const(v): Signal.make(v);
			case Bound(s): s;
			case Derived(c):
				var s = Signal.make(c.get());
				new Watch(() -> c.get(), v -> s.set(v));
				s;
		}
		var range = new ashui.ui.Input({
			type: "range",
			valueAsNumber: value,
			min: props.min,
			max: props.max,
			step: props.step,
			orientation: props.orientation,
			disabled: props.disabled,
			onInput: props.onChange == null ? null : v -> props.onChange(Std.parseFloat(v)),
			name: props.name,
			id: props.id
		}, children);
		ashui.css.Identity.of(range.tree, range.node.id).addClasses(["ui-slider"]);
		if (props.label == null)
			return range;
		var v = value;
		var format = props.format != null ? props.format : (x:Float) -> Std.string(Math.round(x * 100) / 100);
		var header = Library.part("ui-slider-header", null, null, [
			Library.part("ui-slider-label", null, null, [new ashui.ui.Text(props.label)]),
			Library.part("ui-slider-value", null, null, [new ashui.ui.Text(Computed.make(() -> format(v.get())))])
		]);
		var field = Library.part("ui-slider-field", null, null, [header, range]);
		if (props.disabled != null)
			ashui.css.Identity.of(field.tree, field.node.id)
				.bindAttribute("data-disabled", Computed.make(() -> (ashui.input.Interaction.of(range.node).disabled.get() ? "" : null : Null<String>)));
		return field;
	}
}
