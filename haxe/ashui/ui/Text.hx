package ashui.ui;

import ashui.layout.Element;
import ashui.layout.IntoReactive;
import ashui.layout.LayoutTree;
import ashui.layout.PropertyId;
import ashui.types.Color;

typedef TextAttributes = {
	?color:IntoReactive<Color>,
	?fontSize:Single,
	?wrap:Bool
}

class Text extends Element {
	public function new(content:String, ?attr:TextAttributes, tree:LayoutTree) {
		super(tree);

		// Allocate native text measurement context in Rust
		var fs:Single = attr != null && attr.fontSize != null ? attr.fontSize : 16.0;
		var wrap = attr != null && attr.wrap != null ? attr.wrap : true;

		this.node = tree.createTextNode(content, fs, 1.2, wrap);

		if (attr != null) {
			if (attr.color != null)
				node.set(PropertyId.Color, attr.color);
		}
	}
}
