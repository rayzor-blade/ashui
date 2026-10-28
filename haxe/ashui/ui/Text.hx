package ashui.ui;

import ashui.layout.Element;
import ashui.layout.IntoReactive;
import ashui.layout.LayoutTree;
import ashui.layout.Prop;
import ashui.types.Color;

typedef TextAttributes = {
	/** Text color. Inherits the parent text color when omitted. **/
	?color:IntoReactive<Color>,
	/** Font size in layout units. Defaults to 16. **/
	?fontSize:Single,
	/** Wraps text to the available width. Defaults to true. **/
	?wrap:Bool
}

/**
	Displays text from a string, signal, or computed value.

	Use `<text>...</text>` in HXX, or write text directly inside an element.
	Reactive content updates automatically. Text inherits the parent color
	unless a color is supplied.
**/
class Text extends Element {
	/** The displayed content. Signals and computeds update the text reactively. **/
	public final content:IntoReactive<String>;

	static final byNode = new Map<String, Text>();

	/** Returns the text element for a node ID, or null if the node has no text element. **/
	public static function at(id:haxe.Int64):Null<Text>
		return byNode.get(haxe.Int64.toStr(id));

	/** Returns the current string, reading the signal or computed when content is reactive. **/
	public function text():String {
		return switch (content : ReactiveType<String>) {
			case Const(s): s;
			case Bound(s): s.get();
			case Derived(c): c.get();
		}
	}

	public function new(content:IntoReactive<String>, ?attr:TextAttributes, ?tree:LayoutTree) {
		super(tree);
		this.content = content;

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
		ashui.css.Identity.register(this.tree, node, "text");
		var key = haxe.Int64.toStr(node.id);
		byNode.set(key, this);
		ashui.reactive.Owner.onCleanup(() -> byNode.remove(key));

		// Without a colour of its own, text inherits one (see DisplayList.update).
		if (attr != null && attr.color != null)
			node.set(Prop.Color, attr.color);
	}
}
