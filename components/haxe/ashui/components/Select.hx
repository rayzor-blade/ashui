package ashui.components;

import ashui.layout.Element;
import ashui.ui.Component;

typedef SelectProps = {
	> ashui.ui.Select.SelectProps,
	/** Small, medium (default) or large trigger and options (git-bug e8a1b50). **/
	?size:Size
}

/**
	A styled version of the built-in select. Retains its keyboard behavior
	and top-layer option list. Use `SelectItem` for options. Accepts the
	built-in props, including `placeholder`.

	CSS targets: `.ui-select` with `[open]`, `[data-placeholder]` and
	`:disabled`; `.ui-select-item` with `:checked` and `:focus`.
	Target the list with `listbox:has(> .ui-select-item)`.
**/
class Select extends Component<SelectProps> {
	function render():Element {
		Library.use();
		var el = new ashui.ui.Select(props, children);
		var size = props.size == null ? Size.Md : props.size;
		ashui.css.Identity.of(el.tree, el.node.id).addClasses(["ui-select"]).setAttribute("data-size", size);
		// The core picker copies option classes into its top layer, including virtual rows (e8a1b50); options a fragment brings later get them too.
		function sized(options:Array<ashui.ui.Option>):Void
			for (option in options)
				ashui.css.Identity.of(option.tree, option.node.id).addClasses(["ui-select-item-" + (size : String)]);
		sized(el.options());
		el.onOptions = sized;
		return el;
	}
}

/** One of a select's options: the built-in `<option>`, of the class `ui-select-item`, which its row in the list takes too. **/
class SelectItem extends ashui.ui.Option {
	override function render():Element {
		var el = super.render();
		ashui.css.Identity.of(el.tree, el.node.id).addClasses(["ui-select-item"]);
		return el;
	}
}
