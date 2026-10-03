package ashui.ui;

import ashui.input.Focus;
import ashui.input.Interaction;
import ashui.layout.Element;
import ashui.layout.IntoReactive;
import ashui.reactive.Computed;
import ashui.reactive.Owner;
import ashui.reactive.Signal;
import ashui.reactive.Watch;
import ashui.ui.TopLayer;

typedef SelectProps = {
	/** The chosen option's value. A signal is read and written, so the select and your code share it; a constant sets it once. **/
	?value:IntoReactive<String>,

	?disabled:IntoReactive<Bool>,

	/** Its id, which CSS's `#id` and a label's `for` find. **/
	?id:String,

	?name:String,

	/** Called with the new value after the user chooses an option. **/
	?onChange:String->Void
}

private typedef Choice = {
	final option:Option;
	final group:Null<String>;
	final disabled:Bool;
}

/**
	HTML's `<select>`, built in, with its `<option>`s, directly or in
	`<optgroup>`s. It shows the chosen option's label; a click, Enter, Space
	or an arrow key opens its list of options in the top layer, below it.
	In the list the arrows, Home and End move among the enabled options,
	typing jumps to the first whose label starts with what was typed, and
	Enter or a click chooses; Escape, Tab or a click outside closes it
	without choosing. Closed and focused, typing chooses by label too.

	Its look is the user-agent stylesheet's: `select`, its list `listbox`,
	the options in it `option` (`:checked` the chosen one, `:focus` the one
	the keys are on) and the group headings `optgroup`.
**/
class Select extends Component<SelectProps> {
	/** The chosen option's value; the caller's signal when `value` was one. **/
	public var value(default, null):Signal<String>;

	var choices:Array<Choice> = [];
	var button:Div;
	var interaction:Interaction;
	var open:Null<TopEntry> = null;
	var typed = "";
	var typedAt = 0.0;

	function render():Element {
		choices = [];
		for (c in children)
			if (Std.isOfType(c, Option)) {
				var o:Option = cast c;
				choices.push({option: o, group: null, disabled: o.isDisabled()});
			} else if (Std.isOfType(c, Optgroup)) {
				var g:Optgroup = cast c;
				for (o in g.options())
					choices.push({option: o, group: g.props.label, disabled: o.isDisabled() || g.props.disabled == true});
			}
		value = switch props.value {
			case null: Signal.make("");
			case Const(v): Signal.make(v);
			case Bound(s): s;
			case Derived(c):
				var s = Signal.make(c.get());
				new Watch(() -> c.get(), v -> s.set(v));
				s;
		}
		// As HTML's, a select whose value is none of its options' chooses the first that is enabled.
		if (!Lambda.exists(choices, c -> c.option.valueText() == value.get())) {
			var first = Lambda.find(choices, c -> !c.disabled);
			if (first != null)
				value.set(first.option.valueText());
		}
		var label = Computed.make(() -> labelOf(value.get()));
		var chevron = new Svg(ashui.svg.SvgDocument.parse(CHEVRON), {width: 14, height: 14});
		ashui.css.Identity.of(chevron.tree, chevron.node.id).setClasses(["chevron"]);
		button = new Div({tag: "select", id: props.id}, [new Text(label), chevron]);
		if (props.name != null)
			ashui.css.Identity.of(button.tree, button.node.id).setAttribute("name", props.name);
		interaction = Interaction.of(button.node).setFocusable(true);
		if (props.disabled != null)
			interaction.setDisabled(props.disabled);
		interaction.onClick(_ -> if (open == null) show() else open.close());
		interaction.onKeyDown(e -> switch e.key {
			case Named(ArrowDown) | Named(ArrowUp):
				e.preventDefault();
				show();
			case _:
		});
		interaction.onTextInput(e -> {
			var match = typeahead(e.text, choices.filter(c -> !c.disabled));
			if (match != null)
				choose(match.option.valueText(), false);
		});
		Owner.onCleanup(() -> if (open != null) open.close());
		return button;
	}

	function labelOf(v:String):String {
		var c = Lambda.find(choices, c -> c.option.valueText() == v);
		return c == null ? "" : c.option.labelText();
	}

	/** Sets the value, as the user choosing does, and closes the list. **/
	function choose(v:String, close = true):Void {
		var changed = value.get() != v;
		value.set(v);
		if (changed && props.onChange != null)
			props.onChange(v);
		if (close && open != null)
			open.close();
	}

	/** The choice whose label starts with what was typed in the last second, `text` added; null if none. **/
	function typeahead(text:String, among:Array<Choice>):Null<Choice> {
		var now = haxe.Timer.stamp();
		typed = (now - typedAt > 1.0 ? "" : typed) + text.toLowerCase();
		typedAt = now;
		return Lambda.find(among, c -> StringTools.startsWith(c.option.labelText().toLowerCase(), typed));
	}

	/** Opens the list of options in the top layer, under the select, the chosen one focused. **/
	function show():Void {
		if (open != null || interaction.disabled.get())
			return;
		var tree = button.tree;
		var b = tree.getBounds(button.node);
		if (b == null)
			return;
		var owner = new Owner(tree, @:privateAccess this.owner);
		var rows:Array<{interaction:Interaction, choice:Choice}> = [];
		var picker = owner.run(() -> {
			var items:Array<Element> = [];
			var heading:Null<String> = null;
			for (c in choices) {
				if (c.group != null && c.group != heading) {
					heading = c.group;
					items.push(new Div({tag: "optgroup"}, [new Text(c.group)]));
				}
				var row = new Div({tag: "option"}, [new Text(c.option.labelText())]);
				var ri = Interaction.of(row.node).setFocusable(true);
				if (c.disabled)
					ri.setDisabled(true);
				ri.checked.set(c.option.valueText() == value.get());
				var choice = c;
				ri.onClick(_ -> choose(choice.option.valueText()));
				ri.onPointerEnter(_ -> if (!choice.disabled) Focus.set(ri, false));
				rows.push({interaction: ri, choice: c});
				items.push(row);
			}
			new Div({tag: "listbox"}, items);
		});
		var enabled = () -> rows.filter(r -> !r.choice.disabled);
		var pi = Interaction.of(picker.node);
		pi.onKeyDown(e -> {
			var list = enabled();
			var at = Lambda.findIndex(list, r -> r.interaction.focused.get());
			switch e.key {
				case Named(ArrowDown):
					e.preventDefault();
					Focus.set(list[at < 0 ? 0 : Std.int(Math.min(at + 1, list.length - 1))].interaction, true);
				case Named(ArrowUp):
					e.preventDefault();
					Focus.set(list[at < 0 ? 0 : Std.int(Math.max(at - 1, 0))].interaction, true);
				case Named(Home):
					e.preventDefault();
					Focus.set(list[0].interaction, true);
				case Named(End):
					e.preventDefault();
					Focus.set(list[list.length - 1].interaction, true);
				case Named(Enter):
					e.preventDefault();
					if (at >= 0)
						choose(list[at].choice.option.valueText());
				case Named(Tab):
					e.preventDefault();
					open.close();
				case _:
			}
		});
		pi.onTextInput(e -> {
			var match = typeahead(e.text, enabled().map(r -> r.choice));
			if (match != null)
				for (r in rows)
					if (r.choice == match)
						Focus.set(r.interaction, true);
		});
		open = TopLayer.open(tree, picker, Below(b.x, b.y, b.width, b.height), null, () -> {
			open = null;
			owner.dispose();
			Focus.set(interaction, true);
		});
		var chosen = Lambda.find(rows, r -> r.choice.option.valueText() == value.get() && !r.choice.disabled);
		var first = enabled()[0];
		if (chosen != null)
			Focus.set(chosen.interaction, true);
		else if (first != null)
			Focus.set(first.interaction, true);
	}

	/** Whether its list of options is open. **/
	public function isOpen():Bool
		return open != null;

	static final CHEVRON = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M6 9l6 6 6-6"/></svg>';
}
