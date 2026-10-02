package ashui.ui;

import ashui.layout.Element;
import ashui.layout.LayoutTree;
import ashui.reactive.ComputedDynamic;
import ashui.reactive.Owner;
import ashui.reactive.Watch;
import ashui.ui.Div.DivAttributes;

private typedef Row<T> = {value:T, owner:Owner, element:Element};

/**
	A box holding one `item(value)` per value of `each()`, in order. Each item
	is built under its own owner. When the list changes, an item whose value
	is still present (by `==`) keeps its element, and an item no longer present
	is disposed. The update happens at the next `LayoutTree.flush`. hxx lowers
	`<for {value in list}>...</for>` to it.
**/
class For<T> extends Div {
	public function new(each:Void->Array<T>, item:T->Element, ?attr:DivAttributes, ?tree:LayoutTree) {
		super(attr, null, tree);
		var owner = Owner.current;
		var list = new ComputedDynamic<Array<T>>(each);
		var rows:Array<Row<T>> = [];
		new Watch(() -> {
			list.get();
			return list.version;
		}, _ -> {
			var unused = rows;
			var next:Array<Row<T>> = [];
			for (value in (list.get() ?? [])) {
				var i = 0;
				while (i < unused.length && unused[i].value != value)
					i++;
				if (i < unused.length) {
					next.push(unused[i]);
					unused.splice(i, 1);
				} else {
					var rowOwner = new Owner(this.tree, owner);
					next.push({value: value, owner: rowOwner, element: rowOwner.run(() -> item(value))});
				}
			}
			for (row in unused)
				row.owner.dispose();
			rows = next;
			this.tree.replaceChildren(node.id, [for (row in rows) row.element.node.id]);
		});
		Owner.onCleanup(() -> for (row in rows) row.owner.dispose());
	}
}
