package ashui.ui;

import ashui.layout.Element;
import ashui.layout.LayoutTree;
import ashui.reactive.Owner;
import ashui.reactive.Watch;
import ashui.ui.Div.DivAttributes;

/**
	`then()` while `when()` is true and `otherwise()`, if any, while it is
	false, laid out in the element it is placed in, as `For`'s items are.
	Each branch is built under its own owner and disposed when the condition
	flips, taking what it created with it. `when` is tracked like a
	computed, and the switch happens at the next `LayoutTree.flush`. hxx
	lowers `<if {cond}>...<else>...</if>` to it.
**/
class Show extends Div {
	public function new(when:Void->Bool, then:Void->Element, ?otherwise:Void->Element, ?attr:DivAttributes, ?tree:LayoutTree) {
		super(attr, null, tree);
		this.tree.makeFragment(node.id);
		var owner = Owner.current;
		var branch:Null<Owner> = null;
		new Watch(when, shown -> {
			if (branch != null)
				branch.dispose();
			var build = shown ? then : otherwise;
			branch = build == null ? null : new Owner(this.tree, owner);
			if (branch != null)
				appendChild(branch.run(build));
		});
		Owner.onCleanup(() -> if (branch != null) branch.dispose());
	}
}
