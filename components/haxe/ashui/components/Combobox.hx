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
	/** The chosen option's value, "" for none. A signal is read and written; a constant sets it once. **/
	?value:IntoReactive<String>,
	options:Array<ComboboxOption>,
	?placeholder:String,
	/** The search field's placeholder. **/
	?searchPlaceholder:String,
	/** What the list says when nothing matches. **/
	?empty:String,
	?disabled:IntoReactive<Bool>,
	?onChange:String->Void,
	?id:String
}

/**
	A select you can search: a trigger showing the chosen option, or the
	placeholder, that opens a `Command` under it, its search field focused,
	its options filtered as you type; choosing one sets the value and
	closes it. CSS: `.ui-combobox-trigger` (`[data-placeholder]`,
	`[data-state]`, `:disabled`), `.ui-combobox-chevron`, and the command's
	classes on `.ui-combobox-content`.
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
		var icon = new ashui.ui.Svg(chevrons, {width: 14, height: 14});
		ashui.css.Identity.of(icon.tree, icon.node.id).setClasses(["ui-combobox-chevron"]);
		var placeholder = props.placeholder == null ? "Select..." : props.placeholder;
		var shown = Computed.make(() -> {
			var l = labelOf(v.get());
			(l == null ? placeholder : l);
		});
		var trigger = Library.part("ui-combobox-trigger", "button", [
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
		ashui.css.Identity.of(command.tree, command.node.id).addClasses(["ui-combobox-content"]);
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
		return Library.part("ui-combobox", null, null, [trigger]);
	}
}
