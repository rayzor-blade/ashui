package ashui.ui;

import ashui.core.Element;
import ashui.core.LayoutTree;
import ashui.core.BlincNode;
import ashui.layout.PropertyId;
import ashui.layout.IntoReactive;
import ashui.types.Brush;
import ashui.types.CornerRadius;

typedef DivAttributes = {
    ?width: IntoReactive<Single>,
    ?height: IntoReactive<Single>,
    ?bg: IntoReactive<Brush>,
    ?cornerRadius: IntoReactive<CornerRadius>,
    ?opacity: IntoReactive<Single>
}

class Div extends Element {
    public function new(?attr: DivAttributes, ?children: Array<Element>, tree: LayoutTree) {
        super(tree);
        
        // 1. Mint the native layout node in Rust via LayoutTree
        this.node = tree.createNode();

        // 2. Configure properties (Routes Const, Bound, or Computed seamlessly)
        if (attr != null) {
            if (attr.width != null) node.applyF32(PropertyId.Width, attr.width);
            if (attr.height != null) node.applyF32(PropertyId.Height, attr.height);
            if (attr.bg != null) node.applyBrush(PropertyId.Background, attr.bg);
            if (attr.cornerRadius != null) node.applyCornerRadius(PropertyId.CornerRadius, attr.cornerRadius);
            if (attr.opacity != null) node.applyF32(PropertyId.Opacity, attr.opacity);
        }

        // 3. Mount child elements into the tree hierarchy
        if (children != null) {
            for (child in children) {
                appendChild(child);
            }
        }
    }
}