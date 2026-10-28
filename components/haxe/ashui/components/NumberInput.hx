package ashui.components;

import ashui.input.Interaction;
import ashui.layout.Element;
import ashui.layout.IntoReactive;
import ashui.reactive.Signal;
import ashui.reactive.Watch;
import ashui.ui.Component;

typedef NumberInputProps = {
	/** Numeric value. A supplied signal is read and updated; a constant sets the initial value. **/
	?value:IntoReactive<Float>,
	?min:Float,
	?max:Float,
	/** Step size for buttons, arrow keys, and wheel input. Defaults to 1. **/
	?step:Float,
	/** Shows decrement and increment buttons. Defaults to true; hiding them preserves typing, arrow keys, and wheel stepping. **/
	?showStepButtons:Bool,
	/** Control height in layout units: 24 for small, 32 for medium (default), or 40 for large. **/
	?size:Size,
	?disabled:IntoReactive<Bool>,
	?name:String,
	?id:String
}

/**
	A centered numeric input with decrement and increment buttons.
	Uses the built-in number input for editing and validation.
	`Size` scales the field and both buttons; `Lg` preserves the original
	large dimensions (ffc482f).

	Set `showStepButtons=false` to hide the buttons. Manual entry, centered
	alignment and wheel stepping remain available (e1d5d1b).

	CSS targets: `.ui-number-input[data-size]`, `.ui-number-field` and
	`.ui-number-step[data-step="down"|"up"]`. Step buttons support `:disabled`.
	Customize the container with `--ui-input-height` and `--ui-input-radius`.
	Part tokens use `--ui-number-step-*` and `--ui-number-field-*` for width,
	font size and field padding.
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
		function stepper(dir:Int, glyph:String):Element {
			var b = Library.part("ui-number-step", "button", ["step" => (dir < 0 ? "down" : "up")], [new ashui.ui.Text(glyph)]);
			var i = Interaction.of(b.node).setFocusable(true);
			if (props.disabled != null)
				i.setDisabled(props.disabled);
			i.onClick(_ -> field.stepNumber(dir));
			return b;
		}
		var showSteps = props.showStepButtons != false;
		var parts:Array<Element> = showSteps ? [stepper(-1, "−"), field, stepper(1, "+")] : [field];
		var box = Library.part("ui-number-input", null,
			["size" => (props.size == null ? Size.Md : props.size : String), "step-buttons" => (showSteps ? "visible" : "hidden")], parts);
		// Wheel over the field or either button uses the same decimal grid (git-bug 095fab4).
		ashui.input.NumberWheel.bind(box.node, () -> Interaction.of(field.node).disabled.get(), field.stepNumber);
		return box;
	}
}
