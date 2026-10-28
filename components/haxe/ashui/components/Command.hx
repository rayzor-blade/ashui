package ashui.components;

import ashui.input.Interaction;
import ashui.layout.Element;
import ashui.layout.AfterChildren;
import ashui.layout.LayoutTree;
import ashui.reactive.Owner;
import ashui.reactive.Computed;
import ashui.reactive.Signal;
import ashui.ui.Component;

typedef CommandProps = {
	/** Receives the selected item value after the item `onSelect` callback. **/
	?onSelect:String->Void,
	?id:String
}

/**
	A searchable command list with keyboard navigation.

	Place a `CommandInput` above a `CommandList` containing `CommandItem`
	elements. Use `CommandGroup` for headings, `CommandSeparator` between
	groups, and `CommandEmpty` for no matches. Search filters by item value
	and keywords, hiding empty groups and their adjacent separators. Arrows
	move the highlight and Enter selects; focus remains in the search field.

	CSS: `.ui-command`, `.ui-command-input`, `.ui-command-list`,
	`.ui-command-group`, `.ui-command-heading`, `.ui-command-item`,
	`.ui-command-empty`, and `.ui-command-separator`. Items expose
	`[data-selected]`, `[data-hidden]`, and `:disabled`; groups expose `[data-hidden]`.
**/
class Command extends Component<CommandProps> {
	/** Current search text. **/
	public final query = Signal.make("");
	/** Highlighted item value, or an empty string when none is highlighted. **/
	public final active = Signal.make("");

	var items:Array<CommandItem> = [];
	// 6a88875: index mounted parts, including fragment children, using the
	// existing AfterChildren queue; never scan an idle command every frame.
	static final parts = new haxe.ds.ObjectMap<ashui.css.Identity, Component<Dynamic>>();

	@:allow(ashui.components)
	static function register(part:Component<Dynamic>, box:Element):Void {
		var identity = ashui.css.Identity.of(box.tree, box.node.id);
		parts.set(identity, part);
		Owner.onCleanup(() -> parts.remove(identity));
	}

	function render():Element {
		items = [];
		var q = query, a = active;
		var root = Library.part("ui-command", null, null, children, props.id);
		var tree = root.tree, id = root.node.id, owner = Owner.current;
		register(this, root);
		var revision = Signal.make(0);
		var bindings = new haxe.ds.ObjectMap<Component<Dynamic>, Owner>();
		var groups = new haxe.ds.ObjectMap<CommandGroup, Array<CommandItem>>();
		var indexed:Array<Component<Dynamic>> = [];
		var any = Computed.make(() -> {
			revision.get();
			return Lambda.exists(items, it -> it.shown.get());
		});
		function index() {
			var mounted:Array<Component<Dynamic>> = [], next:Array<CommandItem> = [];
			var seen = new haxe.ds.ObjectMap<Component<Dynamic>, Bool>();
			var nextGroups = new haxe.ds.ObjectMap<CommandGroup, Array<CommandItem>>();
			function walk(node:haxe.Int64, group:Null<CommandGroup>) {
				var part = parts.get(ashui.css.Identity.of(tree, node));
				if (part != null) {
					if (Std.isOfType(part, Command)) return; // A nested command owns its own catalog (6a88875).
					mounted.push(part);
					seen.set(part, true);
					if (Std.isOfType(part, CommandGroup)) {
						group = cast part;
						nextGroups.set(group, []);
					} else if (Std.isOfType(part, CommandItem)) {
						var item:CommandItem = cast part;
						next.push(item);
						if (group != null) nextGroups.get(group).push(item);
						return;
					}
				}
				for (child in tree.children(node)) walk(child, group);
			}
			for (child in tree.children(id)) walk(child, null);
			// 08938d7: label/inline-flow changes are not catalog changes and
			// must not cancel the user's manual scroll or invalidate bindings.
			var changed = mounted.length != indexed.length;
			if (!changed) for (i in 0...mounted.length) if (mounted[i] != indexed[i]) { changed = true; break; }
			if (!changed) return;
			indexed = mounted;
			groups = nextGroups;
			items = next;
			for (part => scope in bindings)
				if (!seen.exists(part)) { scope.dispose(); bindings.remove(part); }
			for (part in mounted) {
				if (bindings.exists(part)) continue;
				var scope = new Owner(tree, owner);
				bindings.set(part, scope);
				scope.run(() -> {
					if (Std.isOfType(part, CommandItem)) (cast part : CommandItem).bindTo(this);
					else if (Std.isOfType(part, CommandInput)) (cast part : CommandInput).bindTo(q);
					else if (Std.isOfType(part, CommandList)) (cast part : CommandList).bindTo(this, revision);
					else if (Std.isOfType(part, CommandGroup)) {
						var group:CommandGroup = cast part;
						group.bindTo(Computed.make(() -> {
							revision.get();
							var held = groups.get(group);
							return held != null && Lambda.exists(held, it -> it.shown.get());
						}));
					} else if (Std.isOfType(part, CommandEmpty)) (cast part : CommandEmpty).bindTo(any);
					else if (Std.isOfType(part, CommandSeparator)) (cast part : CommandSeparator).bindTo(Computed.make(() -> q.get() == ""));
				});
			}
			revision.set(revision.get() + 1);
		}
		index();
		AfterChildren.watch(tree, "command " + haxe.Int64.toStr(id),
			parent -> parent == id || tree.ancestors(parent).indexOf(id) >= 0, index);
		Owner.onCleanup(() -> { items = []; indexed = []; groups.clear(); bindings.clear(); });
		// The first item left takes the highlight when the one highlighted is filtered out.
		new ashui.reactive.Watch(() -> {
			revision.get();
			return [for (it in items) if (it.shown.get() && !it.disabled()) it.props.value];
		}, left -> {
			if (left.indexOf(a.get()) < 0)
				a.set(left.length > 0 ? left[0] : "");
		}, (before, after) -> {
			if (before.length != after.length) return false;
			for (i in 0...before.length) if (before[i] != after[i]) return false;
			return true;
		});
		Interaction.of(root.node).onKeyDown(e -> {
			var left = [for (it in items) if (it.shown.get() && !it.disabled()) it];
			if (left.length == 0)
				return;
			var value = a.get();
			var at = Lambda.findIndex(left, it -> it.props.value == value);
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

	@:allow(ashui.components.CommandList)
	function selected():Null<CommandItem> {
		var value = active.get();
		return Lambda.find(items, it -> it.props.value == value && it.shown.get() && !it.disabled());
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

	/** Returns whether every search word occurs in the item value, keywords, or label. **/
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

/** Search field that keeps focus while arrow keys navigate the command list. **/
class CommandInput extends Component<{?placeholder:String, ?id:String}> {
	static var glass:Null<ashui.svg.SvgDocument> = null;
	final text = Signal.make("");
	var field:Null<ashui.ui.Input> = null;

	function render():Element {
		if (glass == null)
			glass = ashui.svg.SvgDocument.of(<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="11" cy="11" r="8"/><path d="m21 21-4.3-4.3"/></svg>);
		var icon = new ashui.ui.Svg(glass);
		ashui.css.Identity.of(icon.tree, icon.node.id).setClasses(["ui-command-search"]);
		field = new ashui.ui.Input({value: text, placeholder: props.placeholder, id: props.id});
		ashui.css.Identity.of(field.tree, field.node.id).addClasses(["ui-command-field"]);
		var box = Library.part("ui-command-input", null, null, [icon, field]);
		Command.register(this, box);
		return box;
	}

	@:allow(ashui.components.Command)
	function bindTo(query:Signal<String>):Void {
		var t = text;
		new ashui.reactive.Watch(() -> t.get(), v -> query.set(v));
	}

	/** Moves focus to the search field. **/
	public function focus():Void
		if (field != null)
			ashui.input.Focus.set(Interaction.of(field.node), false);
}

/** Scrollable container for command items and groups. **/
class CommandList extends Component<{?id:String}> {
	var box:ashui.ui.Div;

	function render():Element {
		box = Library.part("ui-command-list", null, null, children, props.id);
		Command.register(this, box);
		return box;
	}

	@:allow(ashui.components.Command)
	function bindTo(command:Command, revision:Signal<Int>):Void {
		// 08938d7: reveal changes after layout, as Select does. An unchanged
		// selection leaves manual scroll alone and adds no work to idle frames.
		var pending = true, tree = box.tree, id = box.node.id;
		new ashui.reactive.Watch(() -> {active: command.active.get(), query: command.query.get(), version: revision.get()},
			_ -> pending = true, (a, b) -> a.active == b.active && a.query == b.query && a.version == b.version);
		var reveal = (t:LayoutTree) -> {
			if (t != tree || !pending || box.node == null || !tree.inView(id)) return false;
			var scroll = ashui.input.Scroll.of(box.node), list = tree.getBounds(box.node);
			if (scroll == null || list == null || list.height <= 0) return false;
			var selected = command.selected();
			if (selected == null) {
				pending = false;
				return scroll.scrollTo(scroll.x.get(), 0);
			}
			if (tree.ancestors(selected.node.id).indexOf(id) < 0) { pending = false; return false; }
			var row = tree.getBounds(selected.node);
			if (row == null || row.height <= 0) return false;
			pending = false;
			var top = row.y - list.y, bottom = top + row.height, y = scroll.y.get();
			if (top < y) return scroll.scrollTo(scroll.x.get(), top);
			if (bottom > y + list.height) return scroll.scrollTo(scroll.x.get(), bottom - list.height);
			return false;
		};
		LayoutTree.layoutHooks.push(reveal);
		Owner.onCleanup(() -> LayoutTree.layoutHooks.remove(reveal));
	}
}

/** Content displayed when no command matches the search. **/
class CommandEmpty extends Component<{?id:String}> {
	var box:Null<ashui.ui.Div> = null;

	function render():Element {
		box = Library.part("ui-command-empty", null, null, children, props.id);
		Command.register(this, box);
		ashui.text.InlineFlow.attach(box);
		return box;
	}

	@:allow(ashui.components.Command)
	function bindTo(any:Computed<Bool>):Void
		ashui.css.Identity.of(box.tree, box.node.id).bindAttribute("data-hidden", Computed.make(() -> (any.get() ? "" : null : Null<String>)));
}

/** Commands under a heading. Hidden when all contained items are filtered out. **/
class CommandGroup extends Component<{?heading:String, ?id:String}> {
	var box:Null<ashui.ui.Div> = null;

	function render():Element {
		var parts:Array<Element> = [];
		if (props.heading != null)
			parts.push(Library.part("ui-command-heading", null, null, [new ashui.ui.Text(props.heading)]));
		box = Library.part("ui-command-group", null, null, parts.concat(children), props.id);
		Command.register(this, box);
		return box;
	}

	@:allow(ashui.components.Command)
	function bindTo(any:Computed<Bool>):Void
		ashui.css.Identity.of(box.tree, box.node.id).bindAttribute("data-hidden", Computed.make(() -> (any.get() ? null : "" : Null<String>)));
}

/** Separator between groups. Hidden while search filters the list. **/
class CommandSeparator extends Component<{?id:String}> {
	var box:Null<ashui.ui.Div> = null;

	function render():Element {
		box = Library.part("ui-command-separator", null, null, null, props.id);
		Command.register(this, box);
		return box;
	}

	@:allow(ashui.components.Command)
	function bindTo(shown:Computed<Bool>):Void
		ashui.css.Identity.of(box.tree, box.node.id).bindAttribute("data-hidden", Computed.make(() -> (shown.get() ? null : "" : Null<String>)));
}

typedef CommandItemProps = {
	/** Value used for search and selection. **/
	value:String,
	/** Additional search terms. **/
	?keywords:Array<String>,
	?onSelect:Void->Void,
	?disabled:Bool,
	?shortcut:String,
	?id:String
}

/** One selectable command. Children supply its label. **/
class CommandItem extends Component<CommandItemProps> {
	/** Whether this item matches the search. Defaults to true before attachment to a command list. **/
	public final shown = Signal.make(true);
	var box:Null<ashui.ui.Div> = null;
	var command:Null<Command>;

	function render():Element {
		var label = Library.part("ui-command-label", null, null, children);
		ashui.text.InlineFlow.attach(label);
		var parts:Array<Element> = [label];
		if (props.shortcut != null)
			parts.push(Library.part("ui-menu-shortcut", null, null, [new ashui.ui.Text(props.shortcut, {wrap: false})]));
		box = Library.part("ui-command-item", null, null, parts, props.id);
		Command.register(this, box);
		if (props.disabled == true)
			Interaction.of(box.node).setDisabled(true);
		// 6a88875: handlers are installed once even when an item is reindexed.
		Interaction.of(box.node).onPointerEnter(_ -> if (command != null && !disabled()) command.active.set(props.value));
		Interaction.of(box.node).onClick(_ -> if (command != null) command.choose(this));
		return box;
	}

	public function disabled():Bool
		return props.disabled == true;

	@:allow(ashui.components.Command)
	function bindTo(command:Command):Void {
		this.command = command;
		Owner.onCleanup(() -> if (this.command == command) this.command = null);
		var q = command.query, a = command.active, value = props.value, me = this;
		var match = Computed.make(() -> Command.matches(me, q.get()));
		new ashui.reactive.Watch(() -> match.get(), v -> shown.set(v));
		var identity = ashui.css.Identity.of(box.tree, box.node.id);
		identity.bindAttribute("data-hidden", Computed.make(() -> (match.get() ? null : "" : Null<String>)));
		identity.bindAttribute("data-selected", Computed.make(() -> (a.get() == value ? "" : null : Null<String>)));
	}
}
