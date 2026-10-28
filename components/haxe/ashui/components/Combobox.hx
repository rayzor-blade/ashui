package ashui.components;

import ashui.components.Command;
import ashui.input.Interaction;
import ashui.layout.Element;
import ashui.layout.IntoReactive;
import ashui.reactive.Computed;
import ashui.reactive.Signal;
import ashui.reactive.Watch;
import ashui.ui.Component;

typedef ComboboxOption = {value:String, label:String};

typedef ComboboxProps = {
	/** Selected value, or an empty string for none. A supplied signal is read and updated; a constant sets the initial selection. **/
	?value:IntoReactive<String>,
	options:Array<ComboboxOption>,
	?placeholder:String,
	/** Placeholder in the search field. **/
	?searchPlaceholder:String,
	/** Message displayed when no option matches the search. **/
	?empty:String,
	?disabled:IntoReactive<Bool>,
	?onChange:String->Void,
	/** Small, medium (default), or large trigger and search list (e8a1b50). **/
	?size:Size,
	?id:String
}

/**
	A searchable select. The trigger shows the current option or placeholder.
	Opening it focuses a `Command` search field. Typing filters options;
	choosing an option updates the value and closes the popup.

	CSS targets: `.ui-combobox-trigger`, `.ui-combobox-chevron` and
	`.ui-combobox-content`, which also uses the command's classes.
	The trigger exposes `[data-placeholder]`, `[data-state]` and `:disabled`.
**/
class Combobox extends Component<ComboboxProps> {
	public var value(default, null):Signal<String>;

	static var chevrons:Null<ashui.svg.SvgDocument> = null;

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
		var v = value, options = props.options;
		var open = Signal.make(false);
		var labelOf = (x:String) -> {
			var o = Lambda.find(options, o -> o.value == x);
			o == null ? null : o.label;
		};
		if (chevrons == null)
			chevrons = ashui.svg.SvgDocument.of(<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="m7 15 5 5 5-5"/><path d="m7 9 5-5 5 5"/></svg>);
		var icon = new ashui.ui.Svg(chevrons);
		ashui.css.Identity.of(icon.tree, icon.node.id).setClasses(["ui-combobox-chevron"]);
		var placeholder = props.placeholder == null ? "Select..." : props.placeholder;
		var shown = Computed.make(() -> {
			var l = labelOf(v.get());
			(l == null ? placeholder : l);
		});
		var trigger = Library.part("ui-combobox-trigger", "button", [
			"size" => (props.size == null ? Size.Md : props.size : String),
			"placeholder" => Computed.make(() -> (labelOf(v.get()) == null ? "" : null : Null<String>)),
			"state" => Computed.make(() -> (open.get() ? "open" : "closed" : Null<String>))
		], [new ashui.ui.Text(shown), icon], props.id);
		ashui.css.Identity.of(trigger.tree, trigger.node.id).setAttribute("type", "button");
		var ti = Interaction.of(trigger.node).setFocusable(true);
		if (props.disabled != null)
			ti.setDisabled(props.disabled);
		ti.onClick(_ -> open.set(!open.get()));

		var search = new CommandInput({placeholder: props.searchPlaceholder == null ? "Search..." : props.searchPlaceholder});
		var items:Array<Element> = [new CommandEmpty({}, [new ashui.ui.Text(props.empty == null ? "No results found." : props.empty)])];
		for (o in options)
			items.push(new CommandItem({value: o.value, keywords: [o.label]}, [new ashui.ui.Text(o.label)]));
		var command = new Command({
			onSelect: chosen -> {
				// Choosing the chosen one again clears it, as shadcn's does.
				var next = v.get() == chosen ? "" : chosen;
				v.set(next);
				open.set(false);
				if (props.onChange != null)
					props.onChange(next);
			}
		}, [search, new CommandList({}, items)]);
		ashui.css.Identity.of(command.tree, command.node.id).addClasses(["ui-combobox-content"])
			.setAttribute("data-size", props.size == null ? Size.Md : props.size);
		var floating = new Floating(open, command);
		floating.align = "start";
		floating.anchorTo(trigger, "bottom", 4);
		// As wide as the trigger, its search field focused.
		floating.opened = () -> {
			var b = trigger.tree.getBounds(trigger.node);
			if (b != null)
				command.node.set(ashui.layout.Prop.MinWidth, b.width);
			search.focus();
		};
		return Library.part("ui-combobox", null, ["size" => (props.size == null ? Size.Md : props.size : String)], [trigger]);
	}
}
