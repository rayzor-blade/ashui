package ashui.core;

class TextNode extends BlincNode {
    // Only accepts an already-allocated ID from the LayoutTree factory
    public function new(id: haxe.Int64) {
        super(id);
    }
}