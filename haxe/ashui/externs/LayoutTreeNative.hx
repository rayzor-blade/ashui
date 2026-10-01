package ashui.externs;


@:hlNative("blinc_abi")
extern class LayoutTreeNative {
    public static function hl_blinc_tree_new(): hl.Abstract<"blinc_tree">;
    public static function hl_blinc_tree_drop(tree: hl.Abstract<"blinc_tree">): Void;
    
    public static function hl_blinc_tree_create_node(tree: hl.Abstract<"blinc_tree">): haxe.Int64;
    public static function hl_blinc_tree_create_text_node(
        tree: hl.Abstract<"blinc_tree">, content: hl.Bytes, fontSize: Single, 
        lineHeight: Single, wrap: Bool, fontName: hl.Bytes, genericFont: Int, 
        fontWeight: Int, italic: Bool
    ): haxe.Int64;
    
    public static function hl_blinc_tree_add_child(tree: hl.Abstract<"blinc_tree">, parent: haxe.Int64, child: haxe.Int64): Void;
    public static function hl_blinc_tree_remove_node(tree: hl.Abstract<"blinc_tree">, node: haxe.Int64): Void;
    public static function hl_blinc_tree_remove_subtree(tree: hl.Abstract<"blinc_tree">, node: haxe.Int64): Void;
    public static function hl_blinc_tree_clear_children(tree: hl.Abstract<"blinc_tree">, parent: haxe.Int64): Void;
    public static function hl_blinc_tree_replace_children(tree: hl.Abstract<"blinc_tree">, parent: haxe.Int64, children: hl.BytesAccess<haxe.Int64>, len: Int): Void;
}