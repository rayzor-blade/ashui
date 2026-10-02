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
	/** `content` is a string, or a signal or computed of one. **/
	public function new(content:IntoReactive<String>, ?attr:TextAttributes, tree:LayoutTree) {
		super(tree);

		// Allocate native text measurement context in Rust
		var fs:Single = attr != null && attr.fontSize != null ? attr.fontSize : 16.0;
		var wrap = attr != null && attr.wrap != null ? attr.wrap : true;

		switch (content) {
			case Const(s):
				this.node = tree.createTextNode(s, fs, 1.2, wrap);
			case _:
				// The binding supplies the content; it takes effect at the next flush.
				this.node = tree.createTextNode("", fs, 1.2, wrap);
				node.set(PropertyId.TextContent, content);
		}

		if (attr != null) {
			if (attr.color != null)
				node.set(PropertyId.Color, attr.color);
		}
	}
}
