package ashui.components;

import ashui.input.Interaction;
import ashui.layout.Element;
import ashui.reactive.Computed;
import ashui.reactive.Signal;
import ashui.ui.Component;

typedef CommandProps = {
	/** Called with an item's value when it is chosen, after the item's own `onSelect`. **/
	?onSelect:String->Void,
	?id:String
}

/**
	A searchable list of commands, in the manner of cmdk: a `CommandInput`
	over a `CommandList` of `CommandItem`s, grouped by `CommandGroup`s
	with headings and `CommandSeparator`s between, and a `CommandEmpty` for
	when nothing matches. Typing filters the items by their value and
	keywords; groups with nothing left hide, and so does a separator beside
	one. The arrows move the highlight among what is left and Enter chooses
	it; focus stays in the input. CSS: `.ui-command`, `.ui-command-input`,
	`.ui-command-list`, `.ui-command-group` (`[data-hidden]`),
	`.ui-command-heading`, `.ui-command-item` (`[data-selected]`,
	`[data-hidden]`, `:disabled`), `.ui-command-empty`,
	`.ui-command-separator`.
**/
class Command extends Component<CommandProps> {
	/** What is typed in the input. **/
	public final query = Signal.make("");
	/** The value of the item highlighted, "" for none. **/
	public final active = Signal.make("");

	var items:Array<CommandItem> = [];

	function render():Element {
		items = [];
		var groups:Array<CommandGroup> = [], separators:Array<CommandSeparator> = [], empties:Array<CommandEmpty> = [], inputs:Array<CommandInput> = [];
		function walk(list:Array<Element>) {
			for (c in list) {
				if (Std.isOfType(c, CommandItem))
					items.push(cast c);
				else if (Std.isOfType(c, CommandGroup))
					groups.push(cast c);
				else if (Std.isOfType(c, CommandSeparator))
					separators.push(cast c);
				else if (Std.isOfType(c, CommandEmpty))
					empties.push(cast c);
				else if (Std.isOfType(c, CommandInput))
					inputs.push(cast c);
				if (Std.isOfType(c, Component))
					walk(@:privateAccess (cast c : Component<Dynamic>).children);
			}
		}
		walk(children);
		var q = query, a = active;
		for (i in items)
			i.bindTo(this);
		for (inp in inputs)
			inp.bindTo(q);
		for (g in groups)
			g.bindTo(Computed.make(() -> Lambda.exists(g.items(), it -> it.shown.get())));
		var any = Computed.make(() -> Lambda.exists(items, it -> it.shown.get()));
		for (e in empties)
			e.bindTo(any);
		for (s in separators)
			s.bindTo(Computed.make(() -> q.get() == ""));
		// The first item left takes the highlight when the one highlighted is filtered out.
		new ashui.reactive.Watch(() -> [for (it in items) if (it.shown.get() && !it.disabled()) it.props.value].join("\u0000"), visible -> {
			var left = visible == "" ? [] : visible.split("\u0000");
			if (left.indexOf(a.get()) < 0)
				a.set(left.length > 0 ? left[0] : "");
		});
		var root = Library.part("ui-command", null, null, children, props.id);
		Interaction.of(root.node).onKeyDown(e -> {
			var left = [for (it in items) if (it.shown.get() && !it.disabled()) it];
			if (left.length == 0)
				return;
			var at = Lambda.findIndex(left, it -> it.props.value == a.get());
			switch e.key {
				case Named(ArrowDown):
					e.preventDefault();
					a.set(left[at < 0 ? 0 : Std.int(Math.min(at + 1, left.length - 1))].props.value);
				case Named(ArrowUp):
					e.preventDefault();
					a.set(left[at < 0 ? 0 : Std.int(Math.max(at - 1, 0))].props.value);
				case Named(Home):
					e.preventDefault();
					a.set(left[0].props.value);
				case Named(End):
					e.preventDefault();
					a.set(left[left.length - 1].props.value);
				case Named(Enter):
					if (at >= 0) {
						e.preventDefault();
						choose(left[at]);
					}
				case _:
			}
		});
		return root;
	}

	@:allow(ashui.components.CommandItem)
	function choose(item:CommandItem):Void {
		if (item.disabled())
			return;
		if (item.props.onSelect != null)
			item.props.onSelect();
		if (props.onSelect != null)
			props.onSelect(item.props.value);
	}

	/** Whether `item` matches what is typed: every word of it in the item's value, keywords or label. **/
	@:allow(ashui.components.CommandItem)
	static function matches(item:CommandItem, query:String):Bool {
		var q = StringTools.trim(query).toLowerCase();
		if (q == "")
			return true;
		var hay = (item.props.value + " " + (item.props.keywords == null ? "" : item.props.keywords.join(" "))).toLowerCase();
		for (word in q.split(" "))
			if (word != "" && hay.indexOf(word) < 0)
				return false;
		return true;
	}
}

/** The search field over the list; it keeps focus while the arrows move the highlight. **/
class CommandInput extends Component<{?placeholder:String, ?id:String}> {
	static var glass:Null<ashui.svg.SvgDocument> = null;
	final text = Signal.make("");
	var field:Null<ashui.ui.Input> = null;

	function render():Element {
		if (glass == null)
			glass = ashui.svg.SvgDocument.of(<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="11" cy="11" r="8"/><path d="m21 21-4.3-4.3"/></svg>);
		var icon = new ashui.ui.Svg(glass, {width: 16, height: 16});
		ashui.css.Identity.of(icon.tree, icon.node.id).setClasses(["ui-command-search"]);
		field = new ashui.ui.Input({value: text, placeholder: props.placeholder, id: props.id});
		ashui.css.Identity.of(field.tree, field.node.id).addClasses(["ui-command-field"]);
		return Library.part("ui-command-input", null, null, [icon, field]);
	}

	@:allow(ashui.components.Command)
	function bindTo(query:Signal<String>):Void {
		var t = text;
		new ashui.reactive.Watch(() -> t.get(), v -> query.set(v));
	}

	/** Focuses the field, as a combobox does when it opens. **/
	public function focus():Void
		if (field != null)
			ashui.input.Focus.set(Interaction.of(field.node), false);
}

/** The list of groups and items, scrolling past its height. **/
class CommandList extends Component<{?id:String}> {
	function render():Element
		return Library.part("ui-command-list", null, null, children, props.id);
}

/** Shown when nothing matches what is typed. **/
class CommandEmpty extends Component<{?id:String}> {
	var box:Null<ashui.ui.Div> = null;

	function render():Element {
		box = Library.part("ui-command-empty", null, null, children, props.id);
		ashui.text.InlineFlow.attach(box);
		return box;
	}

	@:allow(ashui.components.Command)
	function bindTo(any:Computed<Bool>):Void
		ashui.css.Identity.of(box.tree, box.node.id).bindAttribute("data-hidden", Computed.make(() -> (any.get() ? "" : null : Null<String>)));
}

/** A group of items under a heading; it hides when none of them matches. **/
class CommandGroup extends Component<{?heading:String, ?id:String}> {
	var box:Null<ashui.ui.Div> = null;

	function render():Element {
		var parts:Array<Element> = [];
		if (props.heading != null)
			parts.push(Library.part("ui-command-heading", null, null, [new ashui.ui.Text(props.heading)]));
		box = Library.part("ui-command-group", null, null, parts.concat(children), props.id);
		return box;
	}

	@:allow(ashui.components.Command)
	function items():Array<CommandItem>
		return [for (c in children) if (Std.isOfType(c, CommandItem)) (cast c : CommandItem)];

	@:allow(ashui.components.Command)
	function bindTo(any:Computed<Bool>):Void
		ashui.css.Identity.of(box.tree, box.node.id).bindAttribute("data-hidden", Computed.make(() -> (any.get() ? null : "" : Null<String>)));
}

/** A rule between groups, hidden while a search narrows the list. **/
class CommandSeparator extends Component<{?id:String}> {
	var box:Null<ashui.ui.Div> = null;

	function render():Element {
		box = Library.part("ui-command-separator", null, null, null, props.id);
		return box;
	}

	@:allow(ashui.components.Command)
	function bindTo(shown:Computed<Bool>):Void
		ashui.css.Identity.of(box.tree, box.node.id).bindAttribute("data-hidden", Computed.make(() -> (shown.get() ? null : "" : Null<String>)));
}

typedef CommandItemProps = {
	/** What it is matched and chosen by. **/
	value:String,
	/** More words it matches. **/
	?keywords:Array<String>,
	?onSelect:Void->Void,
	?disabled:Bool,
	?shortcut:String,
	?id:String
}

/** One of the commands; its children are its label. **/
class CommandItem extends Component<CommandItemProps> {
	/** Whether it matches what is typed; true until it is in a command. **/
	public final shown = Signal.make(true);
	var box:Null<ashui.ui.Div> = null;

	function render():Element {
		var label = Library.part("ui-command-label", null, null, children);
		ashui.text.InlineFlow.attach(label);
		var parts:Array<Element> = [label];
		if (props.shortcut != null)
			parts.push(Library.part("ui-menu-shortcut", null, null, [new ashui.ui.Text(props.shortcut, {wrap: false})]));
		box = Library.part("ui-command-item", null, null, parts, props.id);
		if (props.disabled == true)
			Interaction.of(box.node).setDisabled(true);
		return box;
	}

	public function disabled():Bool
		return props.disabled == true;

	@:allow(ashui.components.Command)
	function bindTo(command:Command):Void {
		var q = command.query, a = command.active, value = props.value, me = this;
		var match = Computed.make(() -> Command.matches(me, q.get()));
		new ashui.reactive.Watch(() -> match.get(), v -> shown.set(v));
		var identity = ashui.css.Identity.of(box.tree, box.node.id);
		identity.bindAttribute("data-hidden", Computed.make(() -> (match.get() ? null : "" : Null<String>)));
		identity.bindAttribute("data-selected", Computed.make(() -> (a.get() == value ? "" : null : Null<String>)));
		var i = Interaction.of(box.node);
		i.onPointerEnter(_ -> if (!disabled()) a.set(value));
		i.onClick(_ -> command.choose(this));
	}
}
