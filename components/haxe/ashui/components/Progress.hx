package ashui.components;

import ashui.layout.Element;
import ashui.ui.Component;

typedef ProgressProps = {
	/** How far, of `max`; indeterminate when left out. **/
	?value:ashui.layout.IntoReactive<Float>,
	?max:Float,
	?size:Size,
	?id:String
}

/**
	A progress bar: the built-in `<progress>` in the library's look, its bar
	easing to each new value. CSS: `.ui-progress` (`[data-size]`), its
	`.bar`.
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
