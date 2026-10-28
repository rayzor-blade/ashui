package ashui.layout;

import ashui.layout.LayoutTree;
import ashui.layout.Node;
import ashui.reactive.Owner;

/**
	Base class for UI elements, including `Div`, `Text`, `Image`, and components.

	Each element owns a node in a layout tree. Subclasses create the node and
	attach child nodes to it. Removing the element clears `node` to null.
**/
class Element {
	public var node(default, null):Node;
	public var tree(default, null):LayoutTree;

	/**
		Creates an element in `tree`, or the current owner tree when omitted.
		Elements created within an owner are removed when that owner is disposed.
	**/
	public function new(?tree:LayoutTree) {
		var owner = Owner.current;
		this.tree = tree != null ? tree : owner != null ? owner.tree : null;
		if (this.tree == null)
			throw "an Element needs a tree, or a current Owner to take one from";
		Owner.onCleanup(remove);
	}

	/** Appends a child node after the existing children. **/
	public inline function appendChild(child:Element):Void {
		if (this.node != null && child.node != null) {
			tree.addChild(this.node.id, child.node.id);
		}
	}

	/** Removes this element and all descendant nodes from the layout tree. **/
	public function remove():Void {
		if (node != null) {
			ashui.css.Identity.forgetSubtree(tree, node.id);
			tree.removeSubtree(node.id);
			node = null;
		}
	}
}
