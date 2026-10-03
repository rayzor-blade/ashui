package ashui.ui;

import ashui.input.Interaction;
import ashui.layout.Element;
import ashui.layout.IntoReactive;
import ashui.layout.Prop;
import ashui.reactive.Computed;

typedef ProgressProps = {
	/** How much is done, from 0 to `max`; without it the progress is indeterminate. **/
	?value:IntoReactive<Float>,

	/** What `value` counts up to; 1 by default. **/
	?max:Float,

	?id:String
}

/**
	HTML's `<progress>`, built in: a bar filled to `value` over `max`.
	Without a value it is indeterminate, CSS's `:indeterminate`, and the
	user-agent stylesheet pulses a part-filled bar. Its look is the
	stylesheet's `progress` and its `.bar`.
**/
class Progress extends Component<ProgressProps> {
	function render():Element {
		var max = props.max != null && props.max > 0 ? props.max : 1.0;
		var bar = new Div({classes: ["bar"]});
		var box = new Div({tag: "progress", id: props.id}, [bar]);
		var interaction = Interaction.of(box.node);
		switch props.value {
			case null:
				interaction.indeterminate.set(true);
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
