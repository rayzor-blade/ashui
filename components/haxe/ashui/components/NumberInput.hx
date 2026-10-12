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
	/** What the buttons, arrow keys and wheel move it by; 1 by default. **/
	?step:Float,
	/** Show the minus/plus buttons (default true). Hiding them keeps typing, arrow keys and wheel stepping. **/
	?showStepButtons:Bool,
	/** Small (24px), medium (32px, default) or large (40px). **/
	?size:Size,
	?disabled:IntoReactive<Bool>,
	?name:String,
	?id:String
}

/**
	A number between a − and a + that step it: the built-in
	`<input type="number">` (typed into, its constraints) joined to its two
	buttons in one bordered piece. CSS: `.ui-number-input` (`[data-size]`),
	`.ui-number-step` (`[data-step]` down or up, `:disabled`),
	`.ui-number-field`. The shared `Size` variants scale the field and both
	buttons together; `Lg` keeps the original dimensions (git-bug ffc482f).
	`showStepButtons=false` omits both buttons and keeps the centered editable
	field and its wheel stepping (git-bug e1d5d1b).
	`--ui-input-height` and `-radius` retune the outer box; `--ui-number-step-width`
	and `-font-size`, and `--ui-number-field-width`, `-padding` and `-font-size`
	retune its parts at any size.
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
