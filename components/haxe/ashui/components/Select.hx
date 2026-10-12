package ashui.components;

import ashui.layout.Element;
import ashui.ui.Component;

typedef SelectProps = {
	> ashui.ui.Select.SelectProps,
	/** Small, medium (default) or large trigger and options (git-bug e8a1b50). **/
	?size:Size
}

/**
	A select in the library's look: the built-in `<select>` (its keys, its
	list in the top layer) with the class `ui-select`, and `SelectItem`s
	for its options. It takes the built-in's props, `placeholder` among
	them. CSS: `.ui-select` (`[open]`, `[data-placeholder]`, `:disabled`),
	`.ui-select-item` (`:checked`, `:focus`), and the list,
	`listbox:has(> .ui-select-item)`.
**/
class Select extends Component<SelectProps> {
	function render():Element {
		Library.use();
		var el = new ashui.ui.Select(props, children);
		var size = props.size == null ? Size.Md : props.size;
		ashui.css.Identity.of(el.tree, el.node.id).addClasses(["ui-select"]).setAttribute("data-size", size);
		// The core picker copies option classes into its top layer, including virtual rows (e8a1b50).
		function sizeOption(option:ashui.ui.Option):Void
			ashui.css.Identity.of(option.tree, option.node.id).addClasses(["ui-select-item-" + (size : String)]);
		for (child in children)
			if (Std.isOfType(child, ashui.ui.Option)) sizeOption(cast child);
			else if (Std.isOfType(child, ashui.ui.Optgroup))
				for (option in (cast child : ashui.ui.Optgroup).options()) sizeOption(option);
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
