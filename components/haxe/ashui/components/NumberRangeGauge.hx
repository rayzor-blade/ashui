package ashui.components;

import ashui.components.NumberGauge.NumberGaugeParts;
import ashui.input.Focus;
import ashui.input.Interaction;
import ashui.input.NumberWheel;
import ashui.input.Pointer;
import ashui.layout.Element;
import ashui.layout.IntoReactive;
import ashui.layout.Prop;
import ashui.reactive.Computed;
import ashui.reactive.Signal;
import ashui.reactive.Watch;
import ashui.ui.Component;

typedef NumberRangeGaugeProps = {
	/** The interval's two values; default to min and max. **/
	?lower:IntoReactive<Float>,
	?upper:IntoReactive<Float>,
	/** Bounds default to 0–100; both endpoints snap to step from min. **/
	?min:Float,
	?max:Float,
	?step:Float,
	?size:Size,
	/** Formats the centered interval, e.g. (lo, hi) -> lo + "–" + hi + " °C". **/
	?format:(Float, Float)->String,
	?disabled:IntoReactive<Bool>,
	/** User edits only; endpoints cannot cross. **/
	?onChange:(Float, Float)->Void,
	/** Separate form names for the lower and upper values. **/
	?lowerName:String,
	?upperName:String,
	/** Optional ids for labels targeting either endpoint. **/
	?lowerId:String,
	?upperId:String,
	?id:String
}

/**
	A filled interval with a grip at each edge (git-bug 095fab4). Pointer
	and wheel edits choose the nearest edge; Tab reaches each endpoint
	separately for the built-in range keys. Coincident edges alternate when
	pressed. The underlying inputs retain focus, disabled and form behavior.
	CSS: `.ui-number-range-gauge`, with the same parts as NumberGauge;
	`[data-endpoint="lower"|"upper"]` identifies its two range inputs.
**/
class NumberRangeGauge extends Component<NumberRangeGaugeProps> {
	public var lower(default, null):Signal<Float>;
	public var upper(default, null):Signal<Float>;

	function render():Element {
		Library.use();
		var min = props.min == null ? 0.0 : props.min;
		var max = Math.max(min, props.max == null ? 100.0 : props.max);
		var step = props.step != null && props.step > 0 ? props.step : 1.0;
		NumberGaugeParts.validate(min, max, step);
		function notify() if (props.onChange != null) props.onChange(lower.get(), upper.get());
		var low = new ashui.ui.Input({
			type: "range", valueAsNumber: props.lower == null ? (min : IntoReactive<Float>) : props.lower,
			min: min, max: max, step: step, disabled: props.disabled, name: props.lowerName, id: props.lowerId,
			onInput: _ -> notify()
		});
		var high = new ashui.ui.Input({
			type: "range", valueAsNumber: props.upper == null ? (max : IntoReactive<Float>) : props.upper,
			min: min, max: max, step: step, disabled: props.disabled, name: props.upperName, id: props.upperId,
			onInput: _ -> notify()
		});
		lower = low.valueAsNumber;
		upper = high.valueAsNumber;
		var lo = lower, hi = upper;
		low.rangeLimit = n -> Math.min(n, hi.get());
		high.rangeLimit = n -> Math.max(n, lo.get());
		new Watch(() -> lo.get(), n -> {
			var next = Math.min(NumberGaugeParts.normalize(n, min, max, step), NumberGaugeParts.normalize(hi.get(), min, max, step));
			if (!NumberGaugeParts.same(n, next)) lo.set(next);
		}, NumberGaugeParts.same);
		new Watch(() -> hi.get(), n -> {
			var next = Math.max(NumberGaugeParts.normalize(n, min, max, step), NumberGaugeParts.normalize(lo.get(), min, max, step));
			if (!NumberGaugeParts.same(n, next)) hi.set(next);
		}, NumberGaugeParts.same);
		var lowThumb = NumberGaugeParts.decorate(low, props.size, "lower");
		var highThumb = NumberGaugeParts.decorate(high, props.size, "upper");
		// Both ranges share identical thumb travel. Only their visual parts
		// overlay; the parent delegates edits to the chosen core input.
		low.node.set(Prop.PointerEvents, ashui.types.Style.PointerEvents.None);
		high.node.set(Prop.PointerEvents, ashui.types.Style.PointerEvents.None);
		var format = props.format == null ? (a:Float, b:Float) -> NumberGaugeParts.format(a) + " – " + NumberGaugeParts.format(b) : props.format;
		var label = NumberGaugeParts.label(Computed.make(() -> format(lo.get(), hi.get())));
		var box = Library.part("ui-number-range-gauge", null,
			["size" => (props.size == null ? Size.Md : props.size : String),
			 "focus-visible" => Computed.make(() -> (Interaction.of(low.node).focusVisible.get() || Interaction.of(high.node).focusVisible.get() ? "" : null : Null<String>))],
			[low, high, label].concat(children), props.id);
		var nearMin = NumberGaugeParts.normalize(min + step, min, max, step);
		var nearMax = NumberGaugeParts.normalize(max - step, min, max, step);
		NumberGaugeParts.sizeToBounds(box, label, [format(min, max), format(min, min), format(max, max),
			format(nearMin, nearMax), format(nearMin, nearMin), format(nearMax, nearMax)]);
		var interaction = Interaction.of(box.node);
		var li = Interaction.of(low.node), hiInteraction = Interaction.of(high.node);
		interaction.setDisabled(Computed.make(() -> li.disabled.get() || hiInteraction.disabled.get()));
		var active = low;
		li.onFocus(_ -> active = low);
		hiInteraction.onFocus(_ -> active = high);
		function nearest(x:Float, alternate = false):ashui.ui.Input {
			// The real thumbs account for CSS size overrides and changing bounds.
			var lb = low.tree.getBounds(lowThumb);
			var hb = high.tree.getBounds(highThumb);
			if (lb == null || hb == null) return active;
			var dl = Math.abs(x - lb.x - lb.width / 2), dh = Math.abs(x - hb.x - hb.width / 2);
			return Math.abs(dl - dh) < 0.001 ? (alternate ? (active == low ? high : low) : active) : dl < dh ? low : high;
		}
		interaction.onPointerDown(e -> {
			if (interaction.disabled.get()) return;
			active = nearest(e.x, true);
			Focus.set(Interaction.of(active.node), false);
			active.beginRangeDrag(e.x, e.y);
			e.preventDefault();
			e.stopPropagation();
		});
		NumberWheel.bind(box.node, () -> interaction.disabled.get(), by -> {
			active = nearest(Pointer.at(box.tree).x);
			active.stepNumber(by);
		});
		return box;
	}
}
