package ashui.components;

import ashui.layout.Element;
import ashui.layout.IntoReactive;
import ashui.reactive.Signal;
import ashui.reactive.Watch;
import ashui.ui.Component;

typedef RadioGroupProps = {
	/** The chosen item's value. A signal is read and written; a constant sets it once. **/
	?value:IntoReactive<String>,
	/** "vertical" (the default) or "horizontal". **/
	?orientation:String,
	?name:String,
	?disabled:IntoReactive<Bool>,
	/** Called with the value chosen. **/
	?onValueChange:String->Void,
	?id:String
}

/**
	A set of radios, one chosen: `RadioGroupItem`s, each a built-in
	`<input type="radio">` with its label, sharing the group's value, so the
	arrow keys move among them and choose. CSS: `.ui-radio-group`
	(`[data-orientation]`), `.ui-radio-field` (an item's label), `.ui-radio`
	(the dial, `:checked`, `:disabled`), `.ui-radio-text`.
**/
class RadioGroup extends Component<RadioGroupProps> {
	public var value(default, null):Signal<String>;

	function render():Element {
		value = switch props.value {
			case null: Signal.make("");
			case Const(v): Signal.make(v);
			case Bound(s): s;
			case Derived(c):
				var s = Signal.make(c.get());
				new Watch(() -> c.get(), v -> s.set(v));
				s;
		}
		if (props.onValueChange != null) {
			var first = true, v = value;
			new Watch(() -> v.get(), x -> if (first) first = false else props.onValueChange(x));
		}
		var root = Library.part("ui-radio-group", null, ["orientation" => (props.orientation == null ? "vertical" : props.orientation)], children,
			props.id);
		for (c in children)
			if (Std.isOfType(c, RadioGroupItem))
				(cast c : RadioGroupItem).bindTo(value, props.name, props.disabled);
		return root;
	}
}

/** One of a radio group's choices; its children are the label's text. **/
class RadioGroupItem extends Component<{value:String, ?disabled:IntoReactive<Bool>, ?id:String}> {
	var field:Null<ashui.ui.Label> = null;

	function render():Element {
		Library.use();
		var text = Library.part("ui-radio-text", null, null, children);
		ashui.text.InlineFlow.attach(text);
		field = new ashui.ui.Label({}, [text]);
		ashui.css.Identity.of(field.tree, field.node.id).addClasses(["ui-radio-field"]);
		return field;
	}

	/** Its radio, made once the group gives it the shared value: radios are one set by sharing it. **/
	@:allow(ashui.components.RadioGroup)
	function bindTo(group:Signal<String>, name:Null<String>, disabled:Null<IntoReactive<Bool>>):Void {
		var f = field;
		@:privateAccess this.owner.run(() -> {
			var dial = new ashui.ui.Input({
				type: "radio",
				group: group,
				value: props.value,
				name: name,
				id: props.id,
				disabled: props.disabled != null ? props.disabled : disabled
			});
			ashui.css.Identity.of(dial.tree, dial.node.id).addClasses(["ui-radio"]);
			f.tree.replaceChildren(f.node.id, [dial.node.id].concat(f.tree.children(f.node.id)));
		});
	}
}
