package ashui.components;

import ashui.css.Identity;
import ashui.input.Interaction;
import ashui.input.NumberWheel;
import ashui.layout.Element;
import ashui.layout.IntoReactive;
import ashui.reactive.Computed;
import ashui.reactive.Signal;
import ashui.reactive.Watch;
import ashui.ui.Component;

typedef NumberGaugeProps = {
	/** Shared numeric value; starts at min (0 by default). **/
	?value:IntoReactive<Float>,
	/** Bounds default to 0–100. Values snap to step from min. **/
	?min:Float,
	?max:Float,
	?step:Float,
	/** Sm/Md/Lg are 24/32/40 px high; Md by default. **/
	?size:Size,
	/** Formats the centered value, e.g. n -> n + " %". **/
	?format:Float->String,
	?disabled:IntoReactive<Bool>,
	/** User edits only; programmatic changes do not call it. **/
	?onChange:Float->Void,
	?name:String,
	?id:String
}

/**
	A filled numeric range with a centered value and a flat three-dot grip,
	without step buttons (git-bug 095fab4). Press or drag the fill edge,
	wheel anywhere over it, or use the built-in range's arrows, Page Up/Down
	and Home/End. All edits share the core range's snapping and form behavior.
	CSS: `.ui-number-gauge`, `.fill`, `.rest`, `.thumb`,
	`.ui-number-gauge-grip` and `.ui-number-gauge-value`.
**/
class NumberGauge extends Component<NumberGaugeProps> {
	public var value(default, null):Signal<Float>;

	function render():Element {
		Library.use();
		var min = props.min == null ? 0.0 : props.min;
		var max = props.max == null ? 100.0 : Math.max(min, props.max);
		var step = props.step != null && props.step > 0 ? props.step : 1.0;
		NumberGaugeParts.validate(min, max, step);
		var range = new ashui.ui.Input({
			type: "range", valueAsNumber: props.value == null ? (min : IntoReactive<Float>) : props.value,
			min: min, max: max, step: step, disabled: props.disabled, name: props.name, id: props.id,
			onInput: props.onChange == null ? null : _ -> props.onChange(value.get())
		});
		value = range.valueAsNumber;
		NumberGaugeParts.decorate(range, props.size);
		var v = value;
		new Watch(() -> v.get(), n -> {
			var next = NumberGaugeParts.normalize(n, min, max, step);
			if (!NumberGaugeParts.same(n, next)) v.set(next);
		}, NumberGaugeParts.same);
		var format = props.format == null ? NumberGaugeParts.format : props.format;
		var label = NumberGaugeParts.label(Computed.make(() -> format(v.get())));
		range.tree.addChild(range.node.id, label.node.id);
		for (child in children) range.tree.addChild(range.node.id, child.node.id);
		NumberWheel.bind(range.node, () -> Interaction.of(range.node).disabled.get(), range.stepNumber);
		return range;
	}
}

/** Shared gauge parts; appearance remains in the component stylesheet. **/
@:noCompletion class NumberGaugeParts {
	public static function decorate(range:ashui.ui.Input, size:Null<Size>, ?endpoint:String):ashui.layout.Node {
		Identity.of(range.tree, range.node.id).addClasses(["ui-number-gauge"])
			.setAttribute("data-size", size == null ? Size.Md : size);
		if (endpoint != null) Identity.of(range.tree, range.node.id).setAttribute("data-endpoint", endpoint);
		for (id in range.tree.children(range.node.id)) {
			var identity = Identity.of(range.tree, id);
			if (identity != null && identity.hasClass("thumb")) {
				var grip = Library.part("ui-number-gauge-grip", null, null,
					[for (_ in 0...3) Library.part("ui-number-gauge-dot")]);
				range.tree.addChild(id, grip.node.id);
				return new ashui.layout.Node(id);
			}
		}
		throw "NumberGauge requires a core range input";
	}

	public static function label(text:IntoReactive<String>):Element
		return Library.part("ui-number-gauge-value", null, null, [new ashui.ui.Text(text)]);

	public static function normalize(n:Float, min:Float, max:Float, step:Float):Float
		return ashui.ui.Input.constrainNumber(Math.isFinite(n) ? n : min, min, max, step);

	public static function validate(min:Float, max:Float, step:Float):Void {
		if (!Math.isFinite(min) || !Math.isFinite(max) || !Math.isFinite(step))
			throw "NumberGauge bounds and step must be finite";
	}

	public static function format(n:Float):String
		return Std.string(n);

	public static function same(a:Float, b:Float):Bool
		// Invalid values must reach normalization, including under Ash hybrid (e70f774).
		return Math.isFinite(a) && Math.isFinite(b) && a == b;
}
