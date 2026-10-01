package ashui.core;

import ashui.externs.LayoutTreeNative;

class LayoutTree {
    public var ptr(default, null): hl.Abstract<"blinc_tree">;

    public function new() {
        this.ptr = LayoutTreeNative.hl_blinc_tree_new();
        hl.Gc.setFinalizer(this, finalize);
    }

    public inline function createNode(): BlincNode {
        return new BlincNode(LayoutTreeNative.hl_blinc_tree_create_node(this.ptr));
    }

    public inline function createTextNode(
        content: String, fontSize: Single = 16.0, lineHeight: Single = 1.2, 
        wrap: Bool = true, ?fontName: String, genericFont: Int = 0, 
        fontWeight: Int = 400, italic: Bool = false
    ): TextNode {
        var contentBytes = content != null ? content.bytes : null;
        var fontNameBytes = fontName != null ? fontName.bytes : null;
        
        return new TextNode(LayoutTreeNative.hl_blinc_tree_create_text_node(
            this.ptr, contentBytes, fontSize, lineHeight, wrap, fontNameBytes, genericFont, fontWeight, italic
        ));
    }

    public inline function addChild(parent: haxe.Int64, child: haxe.Int64): Void {
        LayoutTreeNative.hl_blinc_tree_add_child(this.ptr, parent, child);
    }

    public inline function removeSubtree(node: haxe.Int64): Void {
        LayoutTreeNative.hl_blinc_tree_remove_subtree(this.ptr, node);
    }

    public function replaceChildren(parent: haxe.Int64, children: Array<haxe.Int64>): Void {
        if (children.length == 0) {
            LayoutTreeNative.hl_blinc_tree_clear_children(this.ptr, parent);
            return;
        }
        
        // Convert to a native HL array for zero-copy memory transfer
        var nativeArray = new hl.NativeArray<haxe.Int64>(children.length);
        for (i in 0...children.length) nativeArray[i] = children[i];
        
        LayoutTreeNative.hl_blinc_tree_replace_children(this.ptr, parent, nativeArray.getBytes(), children.length);
    }

    static function finalize(obj: LayoutTree) {
        LayoutTreeNative.hl_blinc_tree_drop(obj.ptr);
    }
}