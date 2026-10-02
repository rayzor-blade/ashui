package ashui.ui;

import ashui.layout.Element;
import ashui.layout.LayoutTree;
import ashui.reactive.ComputedBool;
import ashui.reactive.Owner;
import ashui.reactive.Watch;
import ashui.ui.Div.DivAttributes;

/**
	A box holding `then()` while `when()` is true and `otherwise()`, if any,
	while it is false. Each branch is built under its own owner and disposed
	when the condition flips, taking what it created with it. The switch
	happens at the next `LayoutTree.flush`. hxx lowers
	`<if {cond}>...<else>...</if>` to it.
**/
class Show extends Div {
	public function new(when:Void->Bool, then:Void->Element, ?otherwise:Void->Element, ?attr:DivAttributes, ?tree:LayoutTree) {
		super(attr, null, tree);
		var owner = Owner.current;
		var condition = new ComputedBool(when);
		var branch:Null<Owner> = null;
		new Watch(condition.get, shown -> {
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
