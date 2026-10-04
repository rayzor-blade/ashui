package ashui.components;

import ashui.layout.Element;
import ashui.ui.Component;

/**
	A select in the library's look: the built-in `<select>` (its keys, its
	list in the top layer) with the class `ui-select`, and `SelectItem`s
	for its options. It takes the built-in's props, `placeholder` among
	them. CSS: `.ui-select` (`[open]`, `[data-placeholder]`, `:disabled`),
	`.ui-select-item` (`:checked`, `:focus`), and the list,
	`listbox:has(> .ui-select-item)`.
**/
class Select extends Component<ashui.ui.Select.SelectProps> {
	function render():Element {
		Library.use();
		var el = new ashui.ui.Select(props, children);
		ashui.css.Identity.of(el.tree, el.node.id).addClasses(["ui-select"]);
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
