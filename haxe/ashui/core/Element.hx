// ashui.core.Element.hx
package ashui.core;

import ashui.core.LayoutTree;
import ashui.core.BlincNode;

class Element {
    public var node(default, null): BlincNode;
    public var tree(default, null): LayoutTree;

    public function new(tree: LayoutTree) {
        this.tree = tree;
    }

    public inline function appendChild(child: Element): Void {
        if (this.node != null && child.node != null) {
            tree.addChild(this.node, child.node);
        }
    }
}