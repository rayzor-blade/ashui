package ashui.components;

import ashui.layout.Element;
import ashui.layout.IntoReactive;
import ashui.reactive.Signal;
import ashui.reactive.Watch;
import ashui.ui.Component;

typedef RadioGroupProps = {
	/** Selected item value. A supplied signal is read and updated; a constant sets the initial selection. **/
	?value:IntoReactive<String>,
	/** Item layout: `vertical` (default) or `horizontal`. **/
	?orientation:String,
	/** Small, medium (default), or large sizing inherited by items (e8a1b50). **/
	?size:Size,
	?name:String,
	?disabled:IntoReactive<Bool>,
	/** Receives the selected value. **/
	?onValueChange:String->Void,
	?id:String
}

/**
	A group of labeled radio buttons with one selected value.
	Each `RadioGroupItem` uses the built-in radio input and shares the group
	value. Arrow keys move focus and selection between items. CSS:
	`.ui-radio-group[data-orientation]`, `.ui-radio-field`, `.ui-radio` with
	`:checked` and `:disabled`, and `.ui-radio-text`.
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
		var size = props.size == null ? Size.Md : props.size;
		var root = Library.part("ui-radio-group", null, ["orientation" => (props.orientation == null ? "vertical" : props.orientation), "size" => (size : String)], children,
			props.id);
		for (c in children)
			if (Std.isOfType(c, RadioGroupItem))
				(cast c : RadioGroupItem).bindTo(value, props.name, props.disabled, size);
		return root;
	}
}

/** A radio choice with label text supplied by its children. **/
class RadioGroupItem extends Component<{value:String, ?disabled:IntoReactive<Bool>, ?size:Size, ?id:String}> {
	var field:Null<ashui.ui.Label> = null;

	function render():Element {
		Library.use();
		var text = Library.part("ui-radio-text", null, null, children);
		ashui.text.InlineFlow.attach(text);
		field = new ashui.ui.Label({}, [text]);
		ashui.css.Identity.of(field.tree, field.node.id).addClasses(["ui-radio-field"]);
		return field;
	}

	/** Radio input created after the group supplies its shared value signal. **/
	@:allow(ashui.components.RadioGroup)
	function bindTo(group:Signal<String>, name:Null<String>, disabled:Null<IntoReactive<Bool>>, groupSize:Size):Void {
		var f = field;
		var size = props.size == null ? groupSize : props.size;
		ashui.css.Identity.of(f.tree, f.node.id).setAttribute("data-size", size);
		@:privateAccess this.owner.run(() -> {
			var dial = new ashui.ui.Input({
				type: "radio",
				group: group,
				value: props.value,
				name: name,
				id: props.id,
				disabled: props.disabled != null ? props.disabled : disabled
			});
			ashui.css.Identity.of(dial.tree, dial.node.id).addClasses(["ui-radio"]).setAttribute("data-size", size);
			f.tree.replaceChildren(f.node.id, [dial.node.id].concat(f.tree.children(f.node.id)));
		});
	}
}
