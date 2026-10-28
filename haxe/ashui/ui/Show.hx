package ashui.ui;

import ashui.layout.Element;
import ashui.layout.LayoutTree;
import ashui.reactive.Owner;
import ashui.reactive.Watch;
import ashui.ui.Div.DivAttributes;

/**
	Renders `then()` while `when()` is true, or `otherwise()` when false.
	Each branch has its own owner and is disposed when replaced.
	The condition tracks reactive dependencies; changes apply at the next
	`LayoutTree.flush`. Branch contents use the parent element's layout.
	HXX compiles `<if {cond}>...<else>...</if>` to this component.
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
