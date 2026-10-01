package ashui.layout;

import ashui.layout.Node;

class TextNode extends Node {
    // Only accepts an already-allocated ID from the LayoutTree factory
    public function new(id: haxe.Int64) {
        super(id);
    }
}