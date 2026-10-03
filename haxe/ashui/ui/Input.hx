package ashui.ui;

import ashui.input.Events;
import ashui.input.Interaction;
import ashui.layout.Element;
import ashui.layout.IntoReactive;
import ashui.layout.LayoutTree;
import ashui.reactive.Computed;
import ashui.reactive.Owner;
import ashui.reactive.Signal;
import ashui.reactive.Watch;

typedef InputProps = {
	/** HTML's input type: `checkbox` or `radio`. **/
	?type:String,

	/** Whether it is checked. A signal is read and written, so the input and your code share it; a constant sets it once. **/
	?checked:IntoReactive<Bool>,

	/** A checkbox in neither state, until it is clicked; CSS's `:indeterminate`. **/
	?indeterminate:IntoReactive<Bool>,

	/** A radio's value: what its group holds while it is checked. **/
	?value:String,

	/**
		Radios sharing a value: the checked one's, set as one is checked, so
		a radio is checked while the group holds its value. Radios with a
		group form one set for the arrow keys.
	**/
	?group:Signal<String>,

	/** Radios of the same name in a tree form one set, as HTML's do, when they share no `group`. **/
	?name:String,

	?disabled:IntoReactive<Bool>,

	/** Its id, which CSS's `#id` and a label's `for` find. **/
	?id:String,

	/** Called after a click, Space or a label checks or unchecks it, with whether it is checked now. **/
	?onChange:Bool->Void
}

/**
	HTML's `<input>`, built in. A checkbox flips when clicked, when Space is
	released while it has focus, or when its label is clicked; a radio is
	checked the same ways, and the arrow keys move focus to the next or
	previous radio of its set and check it. Disabled, it takes none of that.

	Its look is the user-agent stylesheet's, through `input[type="checkbox"]`,
	`input[type="radio"]`, `:checked`, `:indeterminate`, `:hover`,
	`:focus-visible` and `:disabled`, so CSS or Tw classes restyle it.
**/
class Input extends Component<InputProps> {
	/** Inputs by node, for labels to find. **/
	static final byNode = new Map<String, Input>();

	/** The radios of each tree, in no order; `tree.order()` gives theirs. **/
	static final radios = new haxe.ds.ObjectMap<LayoutTree, Array<Input>>();

	static var checkMark:Null<ashui.svg.SvgDocument> = null;
	static var dashMark:Null<ashui.svg.SvgDocument> = null;

	/** Whether it is checked; the caller's signal when `checked` was one. **/
	public var state(default, null):Signal<Bool>;

	var interaction:Interaction;

	function render():Element {
		var type = props.type == null ? "text" : props.type.toLowerCase();
		if (type != "checkbox" && type != "radio")
			throw 'input: type "$type" is not built in yet; checkbox and radio are';
		var box = new Div({tag: "input", id: props.id});
		var identity = ashui.css.Identity.of(box.tree, box.node.id);
		identity.setAttribute("type", type);
		if (props.name != null)
			identity.setAttribute("name", props.name);
		if (props.value != null)
			identity.setAttribute("value", props.value);
		interaction = Interaction.of(box.node).setFocusable(true);
		if (props.disabled != null)
			interaction.setDisabled(props.disabled);

		state = switch props.checked {
			case null: Signal.make(false);
			case Const(v): Signal.make(v);
			case Bound(s): s;
			case Derived(c):
				var s = Signal.make(c.get());
				new Watch(() -> c.get(), v -> s.set(v));
				s;
		}
		if (type == "radio" && props.group != null) {
			var group = props.group, value = props.value;
			// Checked while the group holds its value; setting the group checks it.
			state.set(group.get() == value);
			new Watch(() -> group.get(), v -> state.set(v == value));
		}
		var checked = interaction.checked;
		checked.set(state.get());
		new Watch(() -> state.get(), v -> checked.set(v));
		switch props.indeterminate {
			case null:
			case Const(v): interaction.indeterminate.set(v);
			case Bound(s): new Watch(() -> s.get(), v -> interaction.indeterminate.set(v));
			case Derived(c): new Watch(() -> c.get(), v -> interaction.indeterminate.set(v));
		}

		if (type == "checkbox") {
			if (checkMark == null) {
				checkMark = ashui.svg.SvgDocument.parse('<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3.5" stroke-linecap="round" stroke-linejoin="round"><path d="M5 12l5 5L20 7"/></svg>');
				dashMark = ashui.svg.SvgDocument.parse('<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3.5" stroke-linecap="round"><path d="M6 12h12"/></svg>');
			}
			var check = new Svg(checkMark, {width: 12, height: 12});
			ashui.css.Identity.of(check.tree, check.node.id).setClasses(["check"]);
			var dash = new Svg(dashMark, {width: 12, height: 12});
			ashui.css.Identity.of(dash.tree, dash.node.id).setClasses(["dash"]);
			box.appendChild(check);
			box.appendChild(dash);
		} else {
			box.appendChild(new Div({classes: ["dot"]}));
			var list = radios.get(box.tree);
			if (list == null)
				radios.set(box.tree, list = []);
			list.push(this);
			var tree = box.tree;
			Owner.onCleanup(() -> {
				var l = radios.get(tree);
				if (l != null)
					l.remove(this);
			});
		}

		var key = haxe.Int64.toStr(box.node.id);
		byNode.set(key, this);
		Owner.onCleanup(() -> byNode.remove(key));

		interaction.onClick(_ -> activate());
		interaction.onKeyDown(e -> {
			switch e.key {
				// Enter does nothing to a checkbox or radio, as in HTML: it would submit a form.
				case Named(Enter):
					e.preventDefault();
				case Named(ArrowDown) | Named(ArrowRight) if (type == "radio"):
					e.preventDefault();
					step(1);
				case Named(ArrowUp) | Named(ArrowLeft) if (type == "radio"):
					e.preventDefault();
					step(-1);
				case _:
			}
		});
		return box;
	}

	/** Checks or flips it, as a click, Space or its label does; nothing while it is disabled. **/
	public function activate():Void {
		if (interaction.disabled.get())
			return;
		var type = props.type.toLowerCase();
		if (type == "checkbox") {
			interaction.indeterminate.set(false);
			state.set(!state.get());
		} else {
			if (isChecked())
				return;
			check();
		}
		if (props.onChange != null)
			props.onChange(state.get());
	}

	/** Whether it is checked now: a grouped radio while its group holds its value, read now rather than when `state` catches up. **/
	public function isChecked():Bool
		return props.group != null && props.type.toLowerCase() == "radio" ? props.group.get() == props.value : state.get();

	/** Checks this radio: its group takes its value, or the others of its name uncheck. **/
	function check():Void {
		if (props.group != null) {
			props.group.set(props.value);
			return;
		}
		state.set(true);
		for (other in set())
			if (other != this)
				other.state.set(false);
	}

	/** The radios of this one's set, in document order: those sharing its group, or else its name. **/
	function set():Array<Input> {
		var all = radios.get(tree);
		if (all == null)
			return [this];
		var mine = all.filter(r -> props.group != null ? r.props.group == props.group : r.props.group == null && r.props.name != null
			&& r.props.name == props.name);
		if (mine.indexOf(this) < 0)
			mine.push(this);
		var order = [for (i => id in tree.order()) haxe.Int64.toStr(id) => i];
		mine.sort((a, b) -> {
			var ia = order.get(haxe.Int64.toStr(a.node.id)), ib = order.get(haxe.Int64.toStr(b.node.id));
			(ia == null ? 0 : ia) - (ib == null ? 0 : ib);
		});
		return mine;
	}

	/** Moves to the next (`by` 1) or previous (-1) enabled radio of the set, wrapping, focuses it and checks it. **/
	function step(by:Int):Void {
		var list = set().filter(r -> r == this || !r.interaction.disabled.get());
		if (list.length < 2)
			return;
		var next = list[(list.indexOf(this) + by + list.length) % list.length];
		ashui.input.Focus.set(next.interaction, true);
		if (!next.isChecked()) {
			next.check();
			if (next.props.onChange != null)
				next.props.onChange(true);
		}
	}

	/** The input at `node` of `tree`, for a label to operate; null if it is none. **/
	public static function at(tree:LayoutTree, node:haxe.Int64):Null<Input>
		return byNode.get(haxe.Int64.toStr(node));
}
