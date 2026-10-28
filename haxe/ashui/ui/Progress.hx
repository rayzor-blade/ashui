package ashui.ui;

import ashui.input.Interaction;
import ashui.layout.Element;
import ashui.layout.IntoReactive;
import ashui.layout.Prop;
import ashui.reactive.Computed;

typedef ProgressProps = {
	/** Completed amount from zero to `max`. Omit for indeterminate progress. **/
	?value:IntoReactive<Float>,

	/** Total amount to complete. Defaults to 1. **/
	?max:Float,

	?id:String
}

/**
	A progress bar, written as `<progress>` in HXX.

	The `.bar` fill shows `value / max`. Omitting `value` applies
	`:indeterminate`, which the user-agent stylesheet displays as a pulsing
	partial bar. Style the control with `progress` and its `.bar` child.
**/
class Progress extends Component<ProgressProps> {
	function render():Element {
		var max = props.max != null && props.max > 0 ? props.max : 1.0;
		var bar = new Div({classes: ["bar"]});
		var box = new Div({tag: "progress", id: props.id}, [bar]);
		var interaction = Interaction.of(box.node);
		switch props.value {
			case null:
				interaction.setIndeterminate(true);
			case Const(v):
				bar.node.set(Prop.WidthPercent, fraction(v, max));
			case Bound(s):
				bar.node.set(Prop.WidthPercent, Computed.make(() -> fraction(s.get(), max)));
			case Derived(c):
				bar.node.set(Prop.WidthPercent, Computed.make(() -> fraction(c.get(), max)));
		}
		return box;
	}

	static function fraction(v:Float, max:Float):Single
		return Math.isNaN(v) ? 0 : Math.max(0, Math.min(1, v / max));
}
