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

	/** Invalid while its value is empty, as when a placeholder or an option with `value=""` shows. **/
	?required:Bool,

	/** Lays out only nearby options in a long, ungrouped list. Each option must have this fixed height, including padding. **/
	?virtualRowHeight:Single,

	/**
		Shown while the value is none of its options', which it may then
		stay rather than choosing the first: "Choose a fruit…". The select
		is marked `[data-placeholder]` while it shows. Not HTML's, which has
		none for a select.
	**/
	?placeholder:String,

	/** Called with the new value after the user chooses an option. **/
	?onChange:String->Void,

	/** Called when it is checked and found invalid, by its form's submit or a script's `checkValidity`, as HTML's `invalid` event. **/
	?onInvalid:Void->Void
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
class Select extends Component<SelectProps> implements FormControl {
	static final byNode = new Map<String, Select>();

	/** The select at `node`, null if it is none, for a form to find. **/
	public static function at(node:haxe.Int64):Null<Select>
		return byNode.get(haxe.Int64.toStr(node));

	/** Its name, which a form submits its value under; null for none. **/
	public function name():Null<String>
		return props.name;

	/** The chosen option's value; the caller's signal when `value` was one. **/
	public var value(default, null):Signal<String>;

	var choices:Array<Choice> = [];
	var button:Div;
	var interaction:Interaction;
	final touched = Signal.make(false);
	var validityOf:FormStates.Validity;
	var initial = "";
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
		var chevron = new Svg(CHEVRON, {width: 14, height: 14});
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
		initial = value.get();
		validityOf = new FormStates.Validity(problems);
		FormStates.keep(interaction, props.required == true, validityOf, touched);
		var key = haxe.Int64.toStr(button.node.id);
		byNode.set(key, this);
		Owner.onCleanup(() -> byNode.remove(key));
		return button;
	}

	function labelOf(v:String):String {
		var c = Lambda.find(choices, c -> c.option.valueText() == v);
		return c == null ? "" : c.option.labelText();
	}

	/** The constraints it breaks now, each with what a browser says of it. **/
	function problems():Array<FormStates.ValidityProblem>
		return props.required == true && value.get() == "" ? [{flag: ValueMissing, message: "Please select an item in the list."}] : [];

	public function formValue():Null<String>
		return value.get();

	/** Whether it is valid now; when it is not, `onInvalid` is called, as HTML fires `invalid`. **/
	public function checkValidity():Bool
		return FormStates.check(this, props.onInvalid);

	/** As `checkValidity`; when it is invalid it is also marked touched and takes focus. **/
	public function reportValidity():Bool {
		if (checkValidity())
			return true;
		touch();
		focus();
		return false;
	}

	/** Which of its constraints it breaks now, as HTML's `ValidityState` says. **/
	public function validity():FormStates.ValidityState
		return validityOf.state();

	/** Why it is invalid, as a browser would say it; empty when it is valid. **/
	public function validationMessage():String
		return validityOf.message();

	/** Makes it invalid with `message`, as HTML's `setCustomValidity` does; empty makes it valid again. **/
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

	/** Sets the value, as the user choosing does, and closes the list. **/
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

	/** The choice whose label starts with what was typed in the last second, `text` added; null if none. **/
	function typeahead(text:String, among:Array<Choice>):Null<Choice> {
		var now = ashui.input.InputClock.now();
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
				ri.checked.set(c.option.valueText() == value.get());
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
			var list = tree.getBounds(picker.node), at = row == null ? null : tree.getBounds(row.node);
			if (row == null || list == null || at == null || list.height <= 0)
				return false;
			wanted = null;
			var top = at.y - list.y, bottom = top + at.height, y = scroll.y.get();
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

	/** The same select and option behaviour with a fixed-height window of rows. **/
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
			var before = new Div({height: Computed.make(() -> (start.get() * rowHeight : Single)), flexShrink: 0});
			var window = new For(() -> [for (i in start.get()...start.get() + visibleCount) i], i -> {
				var c = choices[i];
				var row = new Div({tag: "option", height: rowHeight, flexShrink: 0}, [new Text(c.option.labelText())]);
				var own = ashui.css.Identity.of(tree, c.option.node.id);
				if (own != null && own.classes().length > 0)
					ashui.css.Identity.of(tree, row.node.id).addClasses(own.classes());
				var ri = Interaction.of(row.node).setFocusable(true);
				if (c.disabled)
					ri.setDisabled(true);
				ri.checked.set(c.option.valueText() == value.get());
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

	/** Whether its list of options is open. **/
	public function isOpen():Bool
		return open != null;

	/** Gap the open list keeps from the window's edge. **/
	static inline var LIST_MARGIN = 8.0;

	static final CHEVRON = ashui.svg.SvgDocument.of(<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M6 9l6 6 6-6"/></svg>);
}
