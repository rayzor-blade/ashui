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
	`.square`. The marker holds text either way, so it is a line of the
	item's text tall, and the bullet is set on that line at the middle of
	its lowercase letters.
**/
class Li extends Component<LiProps> {
	static final byNode = new Map<String, Li>();
	static var hooked = false;
	var ordinal = 1;
	var defaultStyle:Null<String> = null;

	/** Its marker's text: its number in an `<ol>`; a space, holding the line, beside a bullet. **/
	public final marker = Signal.make("");

	/** `disc`, `circle` or `square` for a shape, empty for text, `none` to remove the marker and its space. **/
	public final bullet = Signal.make("");

	/** The list-style-type keywords drawn by the existing marker and counter implementations. **/
	@:noCompletion public static function cssType(value:String):String {
		var key = StringTools.trim(value).toLowerCase();
		return switch key {
			case "none" | "disc" | "circle" | "square" | "decimal" | "decimal-leading-zero" | "lower-alpha" | "upper-alpha" | "lower-latin" | "upper-latin" | "lower-roman" | "upper-roman": key;
			case _: throw "list-style-type supports none, disc, circle, square, decimal, decimal-leading-zero, alpha, latin or roman keywords";
		};
	}

	/** Keeps the list's counting rules while CSS chooses how to show this item's ordinal. **/
	@:noCompletion public function mark(number:Int, fallback:String):Void {
		ordinal = number;
		defaultStyle = fallback;
		restyle();
	}

	function restyle():Void {
		if (defaultStyle == null) return;
		var identity = ashui.css.Identity.of(tree, node.id);
		var value = identity == null ? null : ashui.css.Css.resolved(identity, "list-style-type");
		var style = value == null ? defaultStyle : try cssType(value) catch (_:String) defaultStyle;
		switch style {
			case "none":
				marker.set("");
				bullet.set("none");
			case "disc" | "circle" | "square":
				marker.set(" ");
				bullet.set(style);
			case _:
				var type = switch style {
					case "lower-alpha" | "lower-latin": "a";
					case "upper-alpha" | "upper-latin": "A";
					case "lower-roman": "i";
					case "upper-roman": "I";
					case _: "1";
				};
				var label = Lists.Ol.counter(ordinal, type);
				if (style == "decimal-leading-zero" && ordinal > -10 && ordinal < 10)
					label = ordinal < 0 ? "-0" + Std.string(-ordinal) : "0" + label;
				marker.set(label + ".");
				bullet.set("");
		}
	}

	static function hook():Void {
		if (hooked) return;
		hooked = true;
		ashui.css.Css.restyled.push(identity -> {
			var li = at(identity.node.id);
			if (li != null) li.restyle();
		});
		ashui.css.Identity.forgetHooks.push(identity -> byNode.remove(haxe.Int64.toStr(identity.node.id)));
	}

	function render():Element {
		hook();
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
