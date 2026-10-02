package ashui.layout;

import ashui.layout.LayoutTree;
import ashui.layout.Node;
import ashui.reactive.Owner;

class Element {
	public var node(default, null):Node;
	public var tree(default, null):LayoutTree;

	/**
		`tree` defaults to the current owner's. An element built under an
		owner is removed when that owner is disposed.
	**/
	public function new(?tree:LayoutTree) {
		var owner = Owner.current;
		this.tree = tree != null ? tree : owner != null ? owner.tree : null;
		if (this.tree == null)
			throw "an Element needs a tree, or a current Owner to take one from";
		Owner.onCleanup(remove);
	}

	public inline function appendChild(child:Element):Void {
		if (this.node != null && child.node != null) {
			tree.addChild(this.node.id, child.node.id);
		}
	}

	/** Removes this element's node and everything below it from the tree. **/
	public function remove():Void {
		if (node != null) {
			tree.removeSubtree(node.id);
			node = null;
		}
	}
}
