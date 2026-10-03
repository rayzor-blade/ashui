package ashui.ui;

import ashui.layout.Element;
import ashui.layout.IntoReactive;
import ashui.layout.LayoutTree;
import ashui.layout.Prop;
import ashui.types.Color;

typedef TextAttributes = {
	/** Its colour; inherited from the elements it is in by default. **/
	?color:IntoReactive<Color>,
	/** In layout units; 16 by default. **/
	?fontSize:Single,
	/** Whether lines break at the width it is laid out at; true by default. **/
	?wrap:Bool
}

/**
	A run of text. Its content is a string, or a signal or computed of one,
	which it follows. Without a colour of its own it takes the text colour
	of the elements it is in, as in CSS. In a template it is `<text>`, or
	text written directly inside a `<div>`.
**/
class Text extends Element {
	/** `content` is a string, or a signal or computed of one. **/
	public function new(content:IntoReactive<String>, ?attr:TextAttributes, ?tree:LayoutTree) {
		super(tree);

		// The node is measured with this size and wrapping.
		var fs:Single = attr != null && attr.fontSize != null ? attr.fontSize : 16.0;
		var wrap = attr != null && attr.wrap != null ? attr.wrap : true;

		switch (content) {
			case Const(s):
				this.node = this.tree.createTextNode(s, fs, 1.2, wrap);
			case _:
				// The binding supplies the content; it takes effect at the next flush.
				this.node = this.tree.createTextNode("", fs, 1.2, wrap);
				node.set(Prop.TextContent, content);
		}

		// Without a colour of its own, text inherits one (see DisplayList.update).
		if (attr != null && attr.color != null)
			node.set(Prop.Color, attr.color);
	}
}
