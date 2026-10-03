package ashui.ui;

import ashui.layout.Element;
import ashui.layout.IntoReactive;
import ashui.layout.Prop;
import ashui.reactive.Computed;
import ashui.reactive.Watch;

typedef MeterProps = {
	/** The measurement, between `min` and `max`. **/
	?value:IntoReactive<Float>,

	/** The range it is measured in; 0 to 1 by default. **/
	?min:Float,
	?max:Float,

	/** Where the low and high parts of the range end; `min` and `max` by default. **/
	?low:Float,
	?high:Float,

	/** The best value; the middle of the range by default. Which part it is in says which part is good. **/
	?optimum:Float,

	?id:String
}

/**
	HTML's `<meter>`, built in: a gauge of a measurement within a known
	range, as a disk's fullness is. Its `.bar` is filled to the value and
	classed by how good the value is, as HTML judges it from `low`, `high`
	and `optimum`: `.optimum`, `.suboptimum` or `.even-less-good`, which
	the user-agent stylesheet colours as success, warning and error.
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

	/** HTML's judgement of `v`: good in the part of the range the optimum is in, less so next to it, worse beyond. **/
	static function region(v:Float, low:Float, high:Float, optimum:Float):String {
		inline function part(x:Float)
			return x < low ? 0 : x > high ? 2 : 1;
		var best = part(optimum), at = part(v);
		return at == best ? "optimum" : Math.abs(at - best) == 1 ? "suboptimum" : "even-less-good";
	}
}
