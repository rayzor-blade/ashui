package ashui.components;

import ashui.layout.Element;
import ashui.ui.Component;

typedef ProgressProps = {
	/** Completed amount from zero to `max`. Omit for indeterminate progress. **/
	?value:ashui.layout.IntoReactive<Float>,
	?max:Float,
	?size:Size,
	?id:String
}

/**
	A themed progress bar that animates value changes.
	Uses the built-in progress behavior. CSS: `.ui-progress[data-size]`
	and its `.bar` child.
**/
class Progress extends Component<ProgressProps> {
	function render():Element {
		Library.use();
		var el = new ashui.ui.Progress({value: props.value, max: props.max, id: props.id});
		var identity = ashui.css.Identity.of(el.tree, el.node.id);
		identity.addClasses(["ui-progress"]);
		identity.setAttribute("data-size", props.size == null ? Size.Md : props.size);
		return el;
	}
}
