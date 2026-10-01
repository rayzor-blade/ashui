package ashui.layout;

import ashui.layout.LayoutTree;
import ashui.layout.Node;

class Element {
	public var node(default, null):Node;
	public var tree(default, null):LayoutTree;

	public function new(tree:LayoutTree) {
		this.tree = tree;
	}

	public inline function appendChild(child:Element):Void {
		if (this.node != null && child.node != null) {
			tree.addChild(this.node, child.node);
		}
	}
}
