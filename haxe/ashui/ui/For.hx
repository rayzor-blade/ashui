package ashui.ui;

import ashui.layout.Element;
import ashui.layout.LayoutTree;
import ashui.reactive.Owner;
import ashui.reactive.Watch;
import ashui.ui.Div.DivAttributes;

private typedef Row<T> = {value:T, owner:Owner, element:Element};

/**
	Renders `item(value)` for each value in `each()`, preserving list order.
	This component is a fragment with no box. Items participate directly in
	the parent's layout, including its direction, gaps and alignment.

	Each item has its own owner. When the list changes, values still present
	according to `==` retain their elements. Removed items are disposed.
	`each` tracks reactive dependencies; updates apply at the next
	`LayoutTree.flush`. HXX compiles `<for {value in list}>...</for>` to this component.
**/
class For<T> extends Div {
	public function new(each:Void->Array<T>, item:T->Element, ?attr:DivAttributes, ?tree:LayoutTree) {
		super(attr, null, tree);
		this.tree.makeFragment(node.id);
		var owner = Owner.current;
		var rows:Array<Row<T>> = [];
		// The children as last placed: a reconcile that leaves them as they are places nothing, which restyles every sibling.
		var placed:Array<haxe.Int64> = [];
		// Every change to what `each` read reconciles, even when it returns
		// the same array.
		new Watch(each, list -> {
			var unused = rows;
			var next:Array<Row<T>> = [];
			for (value in (list ?? [])) {
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
			var ids = [for (row in rows) row.element.node.id];
			var same = ids.length == placed.length;
			if (same)
				for (i in 0...ids.length)
					if (ids[i] != placed[i]) {
						same = false;
						break;
					}
			if (!same) {
				placed = ids;
				this.tree.replaceChildren(node.id, ids);
			}
		}, (_, _) -> false);
		Owner.onCleanup(() -> for (row in rows)
			row.owner.dispose());
	}
}
