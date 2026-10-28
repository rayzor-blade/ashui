package ashui.ui;

import ashui.layout.Element;
import ashui.layout.IntoReactive;
import ashui.layout.Prop;
import ashui.reactive.Computed;
import ashui.reactive.Watch;

typedef MeterProps = {
	/** Measured value, clamped between `min` and `max`. **/
	?value:IntoReactive<Float>,

	/** Lower bound of the measurement range. The range defaults to 0–1. **/
	?min:Float,
	?max:Float,

	/** Upper boundary of the low region. `high` sets the lower boundary of the high region; defaults are `min` and `max`. **/
	?low:Float,
	?high:Float,

	/** Preferred value. Defaults to the midpoint; its region determines which values are considered optimal. **/
	?optimum:Float,

	?id:String
}

/**
	A gauge for a measurement within a known range, such as disk usage.

	Use `<meter>` in HXX. The `.bar` fill follows `value`. The `low`, `high`,
	and `optimum` bounds select `.optimum`, `.suboptimum`, or `.even-less-good`,
	styled as success, warning, and error by the user-agent stylesheet.
**/
class Meter extends Component<MeterProps> {
	function render():Element {
		var min = props.min != null ? props.min : 0.0;
		var max = props.max != null && props.max > min ? props.max : min + 1;
		var low = props.low != null ? Math.max(min, Math.min(max, props.low)) : min;
		var high = props.high != null ? Math.max(low, Math.min(max, props.high)) : max;
		var optimum = props.optimum != null ? Math.max(min, Math.min(max, props.optimum)) : min + (max - min) / 2;
		var value = Computed.make(() -> {
			var v = switch props.value {
				case null: 0.0;
				case Const(v): v;
				case Bound(s): s.get();
				case Derived(c): c.get();
			}
			Math.isNaN(v) ? min : Math.max(min, Math.min(max, v));
		});
		var bar = new Div({classes: ["bar"]});
		bar.node.set(Prop.WidthPercent, Computed.make(() -> ((value.get() - min) / (max - min) : Single)));
		var identity = ashui.css.Identity.of(bar.tree, bar.node.id);
		new Watch(() -> region(value.get(), low, high, optimum), r -> identity.setClasses(["bar", r]));
		return new Div({tag: "meter", id: props.id}, [bar]);
	}

	/** Classifies a value by its distance in regions from the optimum region. **/
	static function region(v:Float, low:Float, high:Float, optimum:Float):String {
		inline function part(x:Float)
			return x < low ? 0 : x > high ? 2 : 1;
		var best = part(optimum), at = part(v);
		return at == best ? "optimum" : Math.abs(at - best) == 1 ? "suboptimum" : "even-less-good";
	}
}
