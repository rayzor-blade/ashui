package ashui.components;

import ashui.input.Interaction;
import ashui.layout.IntoReactive;
import ashui.layout.Element;
import ashui.ui.Component;

/**
	A table in the library's look: the built-in `<table>`, every row a grid
	of the same columns, with `TableHeader`, `TableBody` and `TableFooter`
	of `TableRow`s of `TableHead` and `TableCell`, and a `TableCaption`
	under it. Rows highlight under the pointer. CSS: `.ui-table`,
	`.ui-table-header`, `.ui-table-body`, `.ui-table-footer`,
	`.ui-table-row` (`:hover`, `[data-state="selected"]`), `.ui-table-head`,
	`.ui-table-cell`, `.ui-table-caption`.
**/
class Table extends Component<{?id:String}> {
	function render():Element {
		Library.use();
		var el = new ashui.ui.Table.Table({id: props.id}, children);
		ashui.css.Identity.of(el.tree, el.node.id).addClasses(["ui-table"]);
		return el;
	}
}

class TableHeader extends Component<{?id:String}> {
	function render():Element
		return Library.part("ui-table-header", "thead", null, children, props.id);
}

class TableBody extends Component<{?id:String}> {
	function render():Element
		return Library.part("ui-table-body", "tbody", null, children, props.id);
}

class TableFooter extends Component<{?id:String}> {
	function render():Element
		return Library.part("ui-table-footer", "tfoot", null, children, props.id);
}

/** A row; `selected` marks it chosen. **/
class TableRow extends Component<{?selected:ashui.layout.IntoReactive<Bool>, ?id:String}> {
	function render():Element {
		var data:Null<Map<String, ashui.layout.IntoReactive<Null<String>>>> = null;
		switch props.selected {
			case null:
			case Const(v): data = ["state" => (v ? "selected" : null : Null<String>)];
			case Bound(s): data = ["state" => ashui.reactive.Computed.make(() -> (s.get() ? "selected" : null : Null<String>))];
			case Derived(c): data = ["state" => ashui.reactive.Computed.make(() -> (c.get() ? "selected" : null : Null<String>))];
		}
		var row = Library.part("ui-table-row", "tr", data, children, props.id);
		// Its hover state, for the highlight under the pointer.
		Interaction.of(row.node);
		return row;
	}
}

class TableHead extends Component<ashui.ui.Table.CellProps> {
	function render():Element {
		var el = new ashui.ui.Table.Th(props, children);
		ashui.css.Identity.of(el.tree, el.node.id).addClasses(["ui-table-head"]);
		return el;
	}
}

class TableCell extends Component<ashui.ui.Table.CellProps> {
	function render():Element {
		var el = new ashui.ui.Table.Td(props, children);
		ashui.css.Identity.of(el.tree, el.node.id).addClasses(["ui-table-cell"]);
		return el;
	}
}

class TableCaption extends Component<{?id:String}> {
	function render():Element {
		var box = Library.part("ui-table-caption", "caption", null, children, props.id);
		ashui.text.InlineFlow.attach(box);
		return box;
	}
}
