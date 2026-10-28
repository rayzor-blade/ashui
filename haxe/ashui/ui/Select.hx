package ashui.ui;

import ashui.input.Focus;
import ashui.input.Interaction;
import ashui.layout.AfterChildren;
import ashui.layout.Element;
import ashui.layout.IntoReactive;
import ashui.reactive.Computed;
import ashui.reactive.Owner;
import ashui.reactive.Signal;
import ashui.reactive.Watch;
import ashui.ui.TopLayer;

typedef SelectProps = {
	/** Selected option value. A supplied signal is read and updated; a constant sets the initial selection. **/
	?value:IntoReactive<String>,

	?disabled:IntoReactive<Bool>,

	/** Element ID used by CSS selectors and a label `for` attribute. **/
	?id:String,

	?name:String,

	/** Requires a nonempty selected value. A placeholder or `value=""` option remains invalid. **/
	?required:Bool,

	/** Enables virtualization for a long, ungrouped option list. All rows must use this fixed height, including padding. **/
	?virtualRowHeight:Single,

	/**
		Label shown when the value matches no option. Allows an empty selection
		instead of choosing the first option, and exposes `[data-placeholder]`.
		This attribute extends the HTML select behavior.
	**/
	?placeholder:String,

	/** Receives the value selected by the user. **/
	?onChange:String->Void,

	/** Runs when form submission or `checkValidity()` finds the control invalid. **/
	?onInvalid:Void->Void
}

private typedef Choice = {
	final option:Option;
	final group:Null<String>;
	final disabled:Bool;
}

/**
	An option picker, written as `<select>` in HXX.

	Supply `<option>` children directly or inside `<optgroup>`. Dynamic
	options from `<for>` and `<if>` are tracked as they change. The closed
	control displays the selected label; click, Enter, Space, or an arrow key
	opens the list in the top layer.

	In the list, arrows, Home, and End move between enabled options. Typing
	searches by label; Enter or a click selects. Escape, Tab, or an outside
	click closes without changing the selection. Typing also selects by label
	when the closed control has focus.

	The user-agent stylesheet uses `select`, `listbox`, `option`, and `optgroup`.
	Options expose `:checked` for selection and `:focus` for keyboard navigation.
**/
class Select extends Component<SelectProps> implements FormControl {
	static final byNode = new Map<String, Select>();

	/** Returns the select registered for a node, or null when absent. **/
	public static function at(node:haxe.Int64):Null<Select>
		return byNode.get(haxe.Int64.toStr(node));

	/** Returns the form field name, or null when unnamed. **/
	public function name():Null<String>
		return props.name;

	/** Current selected value. Uses the supplied signal when available. **/
	public var value(default, null):Signal<String>;

	var choices:Array<Choice> = [];
	final revision = Signal.make(0);
	var button:Div;
	var interaction:Interaction;
	final touched = Signal.make(false);
	var validityOf:FormStates.Validity;
	var initial = "";
	var open:Null<TopEntry> = null;
	var typed = "";
	var typedAt = 0.0;

	/** Maps rendered identities to their option and option-group components. **/
	static final parts = new haxe.ds.ObjectMap<ashui.css.Identity, Component<Dynamic>>();

	@:allow(ashui.ui)
	static function register(part:Component<Dynamic>, box:Element):Void {
		var identity = ashui.css.Identity.of(box.tree, box.node.id);
		parts.set(identity, part);
		Owner.onCleanup(() -> parts.remove(identity));
	}

	/**
		Visits options below a node, including `<for>` and `<if>` fragments, and
		passes each option and its group to `found`. Returns whether a fragment
		was encountered.
	**/
	@:allow(ashui.ui)
	static function walk(tree:ashui.layout.LayoutTree, node:haxe.Int64, group:Null<Optgroup>, found:(Option, Null<Optgroup>) -> Void):Bool {
		var fragment = tree.isFragment(node);
		var part = parts.get(ashui.css.Identity.of(tree, node));
		if (Std.isOfType(part, Option)) {
			found(cast part, group);
			return fragment;
		}
		if (Std.isOfType(part, Optgroup)) {
			if (group != null)
				return fragment;
			group = cast part;
		}
		for (child in tree.children(node))
			if (walk(tree, child, group, found))
				fragment = true;
		return fragment;
	}

	/** Collects options and notes whether fragments can change the list later. **/
	function collect():{choices:Array<Choice>, fragments:Bool} {
		var out:Array<Choice> = [], fragments = false;
		for (c in children)
			if (walk(tree, c.node.id, null, (o, g) -> out.push({
				option: o,
				group: g == null ? null : g.props.label,
				disabled: o.isDisabled() || (g != null && g.props.disabled == true)
			})))
				fragments = true;
		return {choices: out, fragments: fragments};
	}

	/**
		Refreshes options after a fragment changes. Selects the first enabled
		option if the current value is no longer available.
	**/
	function refresh():Void {
		choices = collect().choices;
		if (props.placeholder == null && !Lambda.exists(choices, c -> c.option.valueText() == value.get())) {
			var first = Lambda.find(choices, c -> !c.disabled);
			if (first != null)
				value.set(first.option.valueText());
		}
		revision.set(revision.get() + 1);
		if (onOptions != null)
			onOptions([for (c in choices) c.option]);
	}

	/** Returns the current options in display order. **/
	public function options():Array<Option>
		return [for (c in choices) c.option];

	/** Receives refreshed options after a fragment changes, allowing component libraries to style new options. **/
	@:allow(ashui.components) var onOptions:Null<Array<Option>->Void> = null;

	function render():Element {
		var found = collect();
		choices = found.choices;
		value = switch props.value {
			case null: Signal.make("");
			case Const(v): Signal.make(v);
			case Bound(s): s;
			case Derived(c):
				var s = Signal.make(c.get());
				new Watch(() -> c.get(), v -> s.set(v));
				s;
		}
		// As HTML's, a select whose value is none of its options' chooses the first that is enabled; one with a placeholder shows that instead.
		if (props.placeholder == null && !Lambda.exists(choices, c -> c.option.valueText() == value.get())) {
			var first = Lambda.find(choices, c -> !c.disabled);
			if (first != null)
				value.set(first.option.valueText());
		}
		var placeholder = props.placeholder;
		var label = Computed.make(() -> {
			var l = labelOf(value.get());
			(l == "" && placeholder != null ? placeholder : l);
		});
		var chevron = new Svg(CHEVRON);
		ashui.css.Identity.of(chevron.tree, chevron.node.id).setClasses(["chevron"]);
		button = new Div({tag: "select", id: props.id}, [new Text(label), chevron]);
		if (props.name != null)
			ashui.css.Identity.of(button.tree, button.node.id).setAttribute("name", props.name);
		if (placeholder != null)
			ashui.css.Identity.of(button.tree, button.node.id)
				.bindAttribute("data-placeholder", Computed.make(() -> (labelOf(value.get()) == "" ? "" : null : Null<String>)));
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
		if (found.fragments) {
			var roots = new Map<String, Bool>();
			for (c in children)
				roots.set(haxe.Int64.toStr(c.node.id), true);
			var tree = this.tree;
			AfterChildren.watch(tree, "select " + haxe.Int64.toStr(button.node.id), parent -> roots.exists(haxe.Int64.toStr(parent))
				|| Lambda.exists(tree.ancestors(parent), a -> roots.exists(haxe.Int64.toStr(a))), refresh);
		}
		initial = value.get();
		validityOf = new FormStates.Validity(problems);
		FormStates.keep(interaction, props.required == true, validityOf, touched);
		var key = haxe.Int64.toStr(button.node.id);
		byNode.set(key, this);
		Owner.onCleanup(() -> byNode.remove(key));
		return button;
	}

	function labelOf(v:String):String {
		revision.get();
		var c = Lambda.find(choices, c -> c.option.valueText() == v);
		return c == null ? "" : c.option.labelText();
	}

	/** Returns the current validation failures and their messages. **/
	function problems():Array<FormStates.ValidityProblem>
		return props.required == true && value.get() == "" ? [{flag: ValueMissing, message: "Please select an item in the list."}] : [];

	public function formValue():Null<String>
		return value.get();

	/** Returns whether the value is valid. Calls `onInvalid` when invalid. **/
	public function checkValidity():Bool
		return FormStates.check(this, props.onInvalid);

	/** Checks validity. An invalid control is marked touched and focused. **/
	public function reportValidity():Bool {
		if (checkValidity())
			return true;
		touch();
		focus();
		return false;
	}

	/** Returns the current constraint flags, following HTML `ValidityState`. **/
	public function validity():FormStates.ValidityState
		return validityOf.state();

	/** Returns the validation message, or an empty string when valid. **/
	public function validationMessage():String
		return validityOf.message();

	/** Sets a custom validation error. An empty string clears the custom error. **/
	public function setCustomValidity(message:String):Void
		validityOf.setCustom(message);

	public function touch():Void
		touched.set(true);

	public function reset():Void {
		value.set(initial);
		touched.set(false);
	}

	public function focus():Void
		Focus.set(interaction, true);

	/** Selects a value and optionally closes the list, as user selection does. **/
	function choose(v:String, close = true):Void {
		var changed = value.get() != v;
		// Choosing is the user changing it: `:user-invalid` may show.
		touched.set(true);
		value.set(v);
		if (changed && props.onChange != null)
			props.onChange(v);
		if (close && open != null)
			open.close();
	}

	/** Finds an option by the label prefix typed within the last second, including `text`. Returns null if none matches. **/
	function typeahead(text:String, among:Array<Choice>):Null<Choice> {
		var now = ashui.input.InputClock.now();
		typed = (now - typedAt > 1.0 ? "" : typed) + text.toLowerCase();
		typedAt = now;
		return Lambda.find(among, c -> StringTools.startsWith(c.option.labelText().toLowerCase(), typed));
	}

	/** Opens the options in the top layer below the control and focuses the selected option. **/
	function show():Void {
		if (open != null || interaction.disabled.get())
			return;
		var tree = button.tree;
		var b = tree.getScrolledBounds(button.node);
		if (b == null)
			return;
		var owner = new Owner(tree, @:privateAccess this.owner);
		if (props.virtualRowHeight != null && props.virtualRowHeight > 0 && !Lambda.exists(choices, c -> c.group != null)) {
			showVirtual(tree, b, owner, props.virtualRowHeight);
			return;
		}
		var rows:Array<{interaction:Interaction, choice:Choice, row:Div}> = [];
		var picker = owner.run(() -> {
			var items:Array<Element> = [];
			var heading:Null<String> = null;
			for (c in choices) {
				if (c.group != null && c.group != heading) {
					heading = c.group;
					items.push(new Div({tag: "optgroup"}, [new Text(c.group)]));
				}
				var row = new Div({tag: "option"}, [new Text(c.option.labelText())]);
				// The option's classes, so a stylesheet styles its row in the list as it styles the option.
				var own = ashui.css.Identity.of(tree, c.option.node.id);
				if (own != null && own.classes().length > 0)
					ashui.css.Identity.of(tree, row.node.id).addClasses(own.classes());
				var ri = Interaction.of(row.node).setFocusable(true);
				if (c.disabled)
					ri.setDisabled(true);
				ri.setChecked(c.option.valueText() == value.get());
				var choice = c;
				ri.onClick(_ -> choose(choice.option.valueText()));
				ri.onPointerEnter(_ -> if (!choice.disabled) Focus.set(ri, false));
				rows.push({interaction: ri, choice: c, row: row});
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
					if (at >= 0) choose(list[at].choice.option.valueText());
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
		// As tall as the room below the select or above it, whichever is more; past that it scrolls.
		var rootBounds = tree.root == null ? null : tree.getBounds(tree.root);
		if (rootBounds != null)
			picker.node.set(ashui.layout.Prop.MaxHeight, (Math.max(0, Math.max(rootBounds.height - b.y - b.height, b.y) - LIST_MARGIN) : Single));
		picker.node.set(ashui.layout.Prop.Overflow, ashui.types.Style.Overflow.Scroll);
		var scroll = owner.run(() -> ashui.input.Scroll.attach(picker.node, false, true));
		// The row to keep in view: the focused one, revealed once layout has placed it.
		var wanted:Null<Div> = null;
		function reveal():Bool {
			var row = wanted;
			var list = tree.getBounds(picker.node),
				at = row == null ? null : tree.getBounds(row.node);
			if (row == null || list == null || at == null || list.height <= 0)
				return false;
			wanted = null;
			var top = at.y - list.y,
				bottom = top + at.height,
				y = scroll.y.get();
			if (top < y)
				scroll.scrollTo(0, top);
			else if (bottom > y + list.height)
				scroll.scrollTo(0, bottom - list.height);
			return false;
		}
		owner.run(() -> {
			for (r in rows) {
				var row = r;
				new Watch(() -> row.interaction.focused.get(), f -> if (f) {
					wanted = row.row;
					reveal();
				});
			}
		});
		var revealAfterLayout = (t:ashui.layout.LayoutTree) -> t == tree && wanted != null ? reveal() : false;
		ashui.layout.LayoutTree.layoutHooks.push(revealAfterLayout);
		var identity = ashui.css.Identity.of(tree, button.node.id);
		identity.setAttribute("open", "");
		open = TopLayer.open(tree, picker, Below(b.x, b.y, b.width, b.height), null, () -> {
			ashui.layout.LayoutTree.layoutHooks.remove(revealAfterLayout);
			identity.setAttribute("open", null);
			open = null;
			owner.dispose();
			Focus.set(interaction, Focus.byKeyboard);
		});
		// Its focus ring only after keyboard use, as :focus-visible's.
		var chosen = Lambda.find(rows, r -> r.choice.option.valueText() == value.get() && !r.choice.disabled);
		var first = enabled()[0];
		if (chosen != null)
			Focus.set(chosen.interaction, Focus.byKeyboard);
		else if (first != null)
			Focus.set(first.interaction, Focus.byKeyboard);
	}

	/** Opens a virtualized list of fixed-height option rows using the same selection behavior. **/
	function showVirtual(tree:ashui.layout.LayoutTree, b:ashui.layout.Bounds, owner:Owner, rowHeight:Single):Void {
		var rootBounds = tree.root == null ? null : tree.getBounds(tree.root);
		var maxHeight = rootBounds == null ? 320.0 : Math.max(0, Math.max(rootBounds.height - b.y - b.height, b.y) - LIST_MARGIN);
		var count = choices.length;
		var visibleCount = Std.int(Math.min(count, Math.ceil(maxHeight / rowHeight) + 2));
		var start = Signal.make(0);
		var active = Signal.make(-1);
		var rows = new Map<Int, Interaction>();
		var listInteraction:Null<Interaction> = null;
		var picker = owner.run(() -> {
			var before = new Div({height: Computed.make(() -> (start.get() * rowHeight:Single)), flexShrink: 0});
			var window = new For(() -> [for (i in start.get()...start.get() + visibleCount) i], i -> {
				var c = choices[i];
				var row = new Div({tag: "option", height: rowHeight, flexShrink: 0}, [new Text(c.option.labelText())]);
				var own = ashui.css.Identity.of(tree, c.option.node.id);
				if (own != null && own.classes().length > 0)
					ashui.css.Identity.of(tree, row.node.id).addClasses(own.classes());
				var ri = Interaction.of(row.node).setFocusable(true);
				if (c.disabled)
					ri.setDisabled(true);
				ri.setChecked(c.option.valueText() == value.get());
				ri.onClick(_ -> choose(c.option.valueText()));
				ri.onPointerEnter(_ -> if (!c.disabled) Focus.set(ri, false));
				ri.onFocus(_ -> active.set(i));
				rows.set(i, ri);
				Owner.onCleanup(() -> {
					rows.remove(i);
					if (open != null && ri.focused.get() && listInteraction != null)
						Focus.set(listInteraction, true);
				});
				row;
			});
			var after = new Div({height: Computed.make(() -> ((count - start.get() - visibleCount) * rowHeight : Single)), flexShrink: 0});
			new Div({tag: "listbox", padding: 0}, [before, window, after]);
		});
		picker.node.set(ashui.layout.Prop.MaxHeight, (maxHeight : Single));
		picker.node.set(ashui.layout.Prop.Overflow, ashui.types.Style.Overflow.Scroll);
		var scroll = owner.run(() -> ashui.input.Scroll.attach(picker.node, false, true));
		listInteraction = Interaction.of(picker.node).setFocusable(true);
		function windowAt(y:Float):Void
			start.set(Std.int(Math.max(0, Math.min(count - visibleCount, Math.floor(y / rowHeight) - 1))));
		owner.run(() -> new Watch(() -> scroll.y.get(), windowAt));
		var pending:Null<Int> = null;
		function focusIndex(i:Int):Void {
			if (i < 0 || i >= count || choices[i].disabled)
				return;
			active.set(i);
			var y = scroll.y.get();
			var bounds = tree.getBounds(picker.node);
			var height = bounds == null || bounds.height <= 0 ? maxHeight : bounds.height;
			var target = i * rowHeight < y ? i * rowHeight : (i + 1) * rowHeight > y + height ? (i + 1) * rowHeight - height : y;
			windowAt(target);
			scroll.jumpTo(0, target);
			var row = rows.get(i);
			if (row != null)
				Focus.set(row, true);
			else
				pending = i;
		}
		var enabled = [for (i in 0...count) if (!choices[i].disabled) i];
		listInteraction.onKeyDown(e -> {
			var at = enabled.indexOf(active.get());
			switch e.key {
				case Named(ArrowDown):
					e.preventDefault();
					if (enabled.length > 0) focusIndex(enabled[at < 0 ? 0 : Std.int(Math.min(at + 1, enabled.length - 1))]);
				case Named(ArrowUp):
					e.preventDefault();
					if (enabled.length > 0) focusIndex(enabled[at < 0 ? 0 : Std.int(Math.max(at - 1, 0))]);
				case Named(Home):
					e.preventDefault();
					if (enabled.length > 0) focusIndex(enabled[0]);
				case Named(End):
					e.preventDefault();
					if (enabled.length > 0) focusIndex(enabled[enabled.length - 1]);
				case Named(Enter):
					e.preventDefault();
					if (active.get() >= 0) choose(choices[active.get()].option.valueText());
				case Named(Tab):
					e.preventDefault();
					open.close();
				case _:
			}
		});
		listInteraction.onTextInput(e -> {
			var match = typeahead(e.text, [for (i in enabled) choices[i]]);
			if (match != null)
				focusIndex(choices.indexOf(match));
		});
		var afterLayout = (t:ashui.layout.LayoutTree) -> {
			if (t == tree && pending != null) {
				var row = rows.get(pending);
				if (row != null) {
					pending = null;
					Focus.set(row, true);
				}
			}
			false;
		};
		ashui.layout.LayoutTree.layoutHooks.push(afterLayout);
		var identity = ashui.css.Identity.of(tree, button.node.id);
		identity.setAttribute("open", "");
		open = TopLayer.open(tree, picker, Below(b.x, b.y, b.width, b.height), null, () -> {
			ashui.layout.LayoutTree.layoutHooks.remove(afterLayout);
			identity.setAttribute("open", null);
			open = null;
			owner.dispose();
			Focus.set(interaction, Focus.byKeyboard);
		});
		Focus.set(listInteraction, Focus.byKeyboard);
		var chosen = Lambda.find(enabled, i -> choices[i].option.valueText() == value.get());
		if (chosen != null)
			focusIndex(chosen);
		else if (enabled.length > 0)
			focusIndex(enabled[0]);
	}

	/** Returns whether the option list is open. **/
	public function isOpen():Bool
		return open != null;

	/** Minimum gap between the open list and the window edge. **/
	static inline var LIST_MARGIN = 8.0;

	static final CHEVRON = ashui.svg.SvgDocument.of(<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M6 9l6 6 6-6"/></svg>);
}
