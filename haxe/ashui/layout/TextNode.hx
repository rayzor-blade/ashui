package ashui.layout;

import ashui.layout.Node;

/**
	A node that shows a run of text, measured and wrapped as it is laid out;
	made by `LayoutTree.createTextNode`.
**/
class TextNode extends Node {
    // Takes an id the tree has already made; see `LayoutTree.createTextNode`.
    public function new(id: haxe.Int64) {
        super(id);
    }
}