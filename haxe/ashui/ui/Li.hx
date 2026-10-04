package ashui.ui;

import ashui.layout.Element;
import ashui.layout.LayoutTree;
import ashui.reactive.Computed;
import ashui.reactive.Owner;
import ashui.reactive.Signal;

typedef LiProps = {
	/** In an `<ol>`, the number it shows; the items after it count on from it. **/
	?value:Int,

	?id:String
}

/**
	HTML's `<li>`, built in: an item of a `<ul>` or `<ol>`, its `.marker`
	beside its `.content`. The list it is in sets the marker: a number, or a
	`.bullet` drawn as a shape, the marker classed `.disc`, `.circle` or
	`.square`, so it is the same size in any font. The marker holds text
	either way, so it is as tall as a line of the item's text and the
	bullet is centred on that line.
**/
class Li extends Component<LiProps> {
	static final byNode = new Map<String, Li>();

	/** Its marker's text: its number in an `<ol>`; a space, holding the line, beside a bullet. **/
	public final marker = Signal.make("");

	/** Its bullet in a `<ul>`, by how deep the list is: `disc`, `circle` or `square`; empty for none. **/
	public final bullet = Signal.make("");

	function render():Element {
		var content = new Div({classes: ["content"]}, children);
		var box = new Div({tag: "li", id: props.id}, [
			new Div({classes: Computed.make(() -> bullet.get() == "" ? ["marker"] : ["marker", bullet.get()])}, [
				new Text(marker, {wrap: false}),
				new Div({classes: ["bullet"]})
			]),
			content
		]);
		// Its text and inline elements flow as one paragraph; a list in it takes a line of its own.
		ashui.text.InlineFlow.attach(content);
		var key = haxe.Int64.toStr(box.node.id);
		byNode.set(key, this);
		Owner.onCleanup(() -> byNode.remove(key));
		return box;
	}

	/** The item at `node`, null if it is none. **/
	public static function at(node:haxe.Int64):Null<Li>
		return byNode.get(haxe.Int64.toStr(node));
}
