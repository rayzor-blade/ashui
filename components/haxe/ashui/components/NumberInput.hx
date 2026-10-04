package ashui.components;

import ashui.input.Interaction;
import ashui.layout.Element;
import ashui.layout.IntoReactive;
import ashui.reactive.Signal;
import ashui.reactive.Watch;
import ashui.ui.Component;

typedef NumberInputProps = {
	/** Its number. A signal is read and written; a constant sets it once. **/
	?value:IntoReactive<Float>,
	?min:Float,
	?max:Float,
	/** What − and + move it by; 1 by default. **/
	?step:Float,
	?disabled:IntoReactive<Bool>,
	?name:String,
	?id:String
}

/**
	A number between a − and a + that step it: the built-in
	`<input type="number">` (typed into, its constraints) joined to its two
	buttons in one bordered piece. CSS: `.ui-number-input`,
	`.ui-number-step` (`[data-step]` down or up, `:disabled`),
	`.ui-number-field`.
**/
class NumberInput extends Component<NumberInputProps> {
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
		var field = new ashui.ui.Input({
			type: "number",
			valueAsNumber: value,
			min: props.min,
			max: props.max,
			step: props.step,
			disabled: props.disabled,
			name: props.name,
			id: props.id
		});
		ashui.css.Identity.of(field.tree, field.node.id).addClasses(["ui-number-field"]);
		var v = value;
		var step = props.step == null ? 1.0 : props.step;
		var low = props.min, high = props.max;
		function stepper(dir:Int, glyph:String):Element {
			var b = Library.part("ui-number-step", "button", ["step" => (dir < 0 ? "down" : "up")], [new ashui.ui.Text(glyph)]);
			var i = Interaction.of(b.node).setFocusable(true);
			if (props.disabled != null)
				i.setDisabled(props.disabled);
			i.onClick(_ -> {
				var next = v.get() + dir * step;
				// Rounded to the step's places, so 0.1 steps do not drift.
				next = Math.round(next / step) * step;
				if (low != null)
					next = Math.max(low, next);
				if (high != null)
					next = Math.min(high, next);
				v.set(next);
			});
			return b;
		}
		return Library.part("ui-number-input", null, null, [stepper(-1, "−"), field, stepper(1, "+")]);
	}
}
