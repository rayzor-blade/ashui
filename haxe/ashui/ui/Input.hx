package ashui.ui;

import ashui.input.Events;
import ashui.input.Interaction;
import ashui.input.Pointer;
import ashui.layout.Prop;
import ashui.layout.Element;
import ashui.layout.IntoReactive;
import ashui.layout.LayoutTree;
import ashui.reactive.Computed;
import ashui.reactive.Owner;
import ashui.reactive.Signal;
import ashui.reactive.Watch;

typedef InputProps = {
	/** HTML's input type: `checkbox`, `radio`, `range`, `number`, or a text type: `text` (the default), `password`, `search`, `email`, `tel` or `url`. **/
	?type:String,

	/** Whether it is checked. A signal is read and written, so the input and your code share it; a constant sets it once. **/
	?checked:IntoReactive<Bool>,

	/** A checkbox in neither state, until it is clicked; CSS's `:indeterminate`. **/
	?indeterminate:IntoReactive<Bool>,

	/**
		Its value as text. A text input's or a number's: a signal is read and
		written, as `checked` is. A radio's: what its group holds while it is
		checked. A range's: where it starts, unless `valueAsNumber` is given.
	**/
	?value:IntoReactive<String>,

	/** A number's or a range's value, read and written when a signal; NaN while a number input is empty. **/
	?valueAsNumber:IntoReactive<Float>,

	/** A number's or a range's bounds and the step its value moves by; a range is 0 to 100 in steps of 1 by default. **/
	?min:Float,
	?max:Float,
	?step:Float,

	/** A range's axis: horizontal (the default) or vertical, increasing from bottom to top. **/
	?orientation:String,

	/** Shown, dimmed, while a text input or a number is empty; CSS's `:placeholder-shown` meanwhile. **/
	?placeholder:String,

	/** Must be filled in, ticked, or one of its radios chosen, for it to be valid, and for a form it is in to submit. **/
	?required:Bool,

	/** A text input's value must match this regular expression, the whole value. **/
	?pattern:String,

	/** A text input's least and greatest length; no more than `maxlength` can be typed or pasted. **/
	?minlength:Int,
	?maxlength:Int,

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

	/** A checkbox's or a radio's: called after a click, Space or a label checks or unchecks it, with whether it is checked now. **/
	?onChange:Bool->Void,

	/** A text input's, a number's or a range's: called with the value as text after each edit, step or drag. **/
	?onInput:String->Void
}

/**
	HTML's `<input>`, built in. A checkbox flips when clicked, when Space is
	released while it has focus, or when its label is clicked; a radio is
	checked the same ways, and the arrow keys move focus to the next or
	previous radio of its set and check it. Disabled, it takes none of that.

	A text input is a `TextField`: `password` shows dots and refuses copying,
	and Escape empties a `search`. A `number` is one that takes only what a
	number is written with; the up and down arrows, or its steppers, move it
	by `step` within `min` and `max`. A `range` is a slider: pressing or
	dragging along it sets the value, as do the arrows, Page Up and Page
	Down (a tenth of the range), Home and End.

	It is valid by HTML's constraints: `required`, `pattern`, `minlength`
	and `maxlength`, an `email` or `url` well formed, a `number` within `min`
	and `max` and on its `step`. CSS reads that as `:valid` and `:invalid`,
	and as `:user-valid` and `:user-invalid` once the user has changed it and
	left it, or a form it is in was submitted; `checkValidity` and
	`validationMessage` read it too. `reset` puts its first value back.

	Its look is the user-agent stylesheet's, through `input[type="..."]`,
	`:checked`, `:indeterminate`, `:hover`, `:focus`, `:focus-visible` and
	`:disabled`, so CSS or Tw classes restyle it. A range's parts are
	`.fill`, `.thumb` and `.rest`; a number's steppers `.steppers` with
	`.step-up` and `.step-down`.
**/
class Input extends Component<InputProps> implements FormControl {
	/** Inputs by node, for labels to find. **/
	static final byNode = new Map<String, Input>();

	/** The radios of each tree, in no order; `tree.order()` gives theirs. **/
	static final radios = new haxe.ds.ObjectMap<LayoutTree, Array<Input>>();

	static var checkMark:Null<ashui.svg.SvgDocument> = null;
	static var dashMark:Null<ashui.svg.SvgDocument> = null;

	/** Whether it is checked; the caller's signal when `checked` was one. **/
	public var state(default, null):Signal<Bool>;

	/** A text input's or a number's text; the caller's signal when `value` was one. **/
	public var value(default, null):Null<Signal<String>> = null;

	/** A number's or a range's value; the caller's signal when `valueAsNumber` was one. **/
	public var valueAsNumber(default, null):Null<Signal<Float>> = null;

	/** A text input's or a number's editing: its caret, selection and what it shows. **/
	public var editing(default, null):Null<TextEditing> = null;

	var interaction:Interaction;

	/** Changed by the user and left, or its form submitted: `:user-invalid` shows from then on. **/
	final touched = Signal.make(false);

	/** Edited since it took focus, so leaving it touches it. **/
	var edited = false;

	/** What `reset` puts back. **/
	var initial:{text:Null<String>, checked:Bool, group:Null<String>} = {text: null, checked: false, group: null};

	function render():Element {
		var type = props.type == null ? "text" : props.type.toLowerCase();
		state = Signal.make(false);
		var el = switch type {
			case "checkbox" | "radio": checkable(type);
			case "range": range();
			case "number": textual(type);
			case t if (TEXT_TYPES.indexOf(t) >= 0): textual(type);
			case _: throw 'input: type "$type" is not built in; checkbox, radio, range, number and ${TEXT_TYPES.join(", ")} are';
		}
		var key = haxe.Int64.toStr(el.node.id);
		byNode.set(key, this);
		Owner.onCleanup(() -> byNode.remove(key));
		constrain(type);
		return el;
	}

	/** Keeps its form states, those CSS reads, as its value and constraints make them. **/
	function constrain(type:String):Void {
		var i = interaction;
		initial = {text: value != null ? value.get() : null, checked: state.get(), group: props.group != null ? props.group.get() : null};
		FormStates.keep(i, props.required == true, problem, touched);
		if (value != null && props.placeholder != null) {
			var text = value;
			new Watch(() -> text.get() == "", empty -> i.formState("placeholder-shown").set(empty));
		}
		// Leaving it after an edit touches it.
		i.onBlur(_ -> if (edited) touched.set(true));
		i.onFocus(_ -> edited = false);
	}

	/** Why it is invalid, as a browser says it, or null when it is valid. **/
	function problem():Null<String> {
		var type = props.type == null ? "text" : props.type.toLowerCase();
		switch type {
			case "checkbox":
				return props.required == true && !state.get() ? "Please tick this box if you want to proceed." : null;
			case "radio":
				if (props.required != true)
					return null;
				var chosen = props.group != null ? props.group.get() != null && props.group.get() != "" : Lambda.exists(set(), r -> r.state.get());
				return chosen ? null : "Please select one of these options.";
			case "range":
				return null;
			case _:
		}
		var v = value == null ? "" : value.get();
		if (v == "")
			return props.required == true ? "Please fill in this field." : null;
		if (type == "number") {
			var n = parseNumber(v);
			if (Math.isNaN(n))
				return "Please enter a number.";
			if (props.min != null && n < props.min)
				return 'Value must be greater than or equal to ${formatNumber(props.min)}.';
			if (props.max != null && n > props.max)
				return 'Value must be less than or equal to ${formatNumber(props.max)}.';
			if (props.step != null && props.step > 0 && !same(snap(n, props.min, null, props.step), n))
				return "Please enter a valid value.";
			return null;
		}
		if (type == "email" && !~/^[^\s@]+@[^\s@.]+(\.[^\s@.]+)*$/.match(v))
			return v.indexOf("@") < 0 ? 'Please include an "@" in the email address.' : "Please enter an email address.";
		if (type == "url" && !~/^[a-zA-Z][a-zA-Z0-9+.-]*:[^\s]+$/.match(v))
			return "Please enter a URL.";
		if (props.pattern != null && !(try new EReg("^(?:" + props.pattern + ")$", "u").match(v) catch (_:Dynamic) true))
			return "Please match the requested format.";
		// As a browser, too short only once the user has edited it.
		return FormStates.lengthProblem(v, props.minlength, props.maxlength, touched.get());
	}

	/** Whether it is valid now. **/
	public function checkValidity():Bool
		return problem() == null;

	/** Why it is invalid, as a browser would say it; empty when it is valid. **/
	public function validationMessage():String {
		var p = problem();
		return p == null ? "" : p;
	}

	/** Marks it as the user having changed it, as submitting its form does, so `:user-invalid` shows. **/
	public function touch():Void
		touched.set(true);

	/** Puts back the value it was built with, checked or not, and untouched, as a form's reset does. **/
	public function reset():Void {
		if (value != null && initial.text != null)
			value.set(initial.text);
		if (props.group != null && initial.group != null)
			props.group.set(initial.group);
		else
			state.set(initial.checked);
		touched.set(false);
	}

	/** Its name, which a form submits its value under; null for none. **/
	public function name():Null<String>
		return props.name;

	/** What a form submits for it: its value, a checkbox's or radio's only while checked; null for nothing. **/
	public function formValue():Null<String> {
		var type = props.type == null ? "text" : props.type.toLowerCase();
		return switch type {
			case "checkbox": state.get() ? (constValue() != null ? constValue() : "on") : null;
			case "radio": isChecked() ? constValue() : null;
			case "range": valueAsNumber != null ? formatNumber(valueAsNumber.get()) : null;
			case _: value != null ? value.get() : null;
		}
	}

	/** Whether it is a text input or a number, where Enter submits its form. **/
	public function submitsOnEnter():Bool {
		var type = props.type == null ? "text" : props.type.toLowerCase();
		return type == "number" || TEXT_TYPES.indexOf(type) >= 0;
	}

	/** Takes focus, as a form does to the first control that is invalid. **/
	public function focus():Void
		ashui.input.Focus.set(interaction, true);

	static final TEXT_TYPES = ["text", "password", "search", "email", "tel", "url"];

	/** The value prop as a constant, for a radio's or a checkbox's; null when it is not one. **/
	function constValue():Null<String>
		return switch props.value {
			case Const(v): v;
			case Bound(s): s.get();
			case Derived(c): c.get();
			case null: null;
		}

	function checkable(type:String):Element {
		var box = new Div({tag: "input", id: props.id});
		var identity = ashui.css.Identity.of(box.tree, box.node.id);
		identity.setAttribute("type", type);
		if (props.name != null)
			identity.setAttribute("name", props.name);
		var radioValue = constValue();
		if (radioValue != null)
			identity.setAttribute("value", radioValue);
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
			var group = props.group, value = radioValue;
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
				checkMark = ashui.svg.SvgDocument.of(<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3.5" stroke-linecap="round" stroke-linejoin="round"><path d="M5 12l5 5L20 7"/></svg>);
				dashMark = ashui.svg.SvgDocument.of(<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3.5" stroke-linecap="round"><path d="M6 12h12"/></svg>);
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

	/** A text input, or a number: a `TextField`, with a number's steppers inside it. **/
	function textual(type:String):Element {
		var text = switch props.value {
			case Bound(s): s;
			case Const(v): Signal.make(v);
			case Derived(c):
				var s = Signal.make(c.get());
				new Watch(() -> c.get(), v -> s.set(v));
				s;
			case null: Signal.make("");
		}
		value = text;
		var steppers:Array<Element> = [];
		if (type == "number") {
			var n = valueAsNumber = numberState(parseNumber(text.get()));
			if (!same(parseNumber(text.get()), n.get()))
				text.set(formatNumber(n.get()));
			// The text and the number follow each other; text that is no number yet, as "1e" is while typed, leaves the number.
			new Watch(() -> text.get(), t -> {
				var v = parseNumber(t);
				if ((t == "" || !Math.isNaN(v)) && !same(v, n.get()))
					n.set(v);
			});
			new Watch(() -> n.get(), v -> if (!same(parseNumber(text.get()), v)) text.set(formatNumber(v)));
			var up = new Div({classes: ["step-up"]}, [new Svg(chevron(true), {width: 10, height: 10})]);
			var down = new Div({classes: ["step-down"]}, [new Svg(chevron(false), {width: 10, height: 10})]);
			Interaction.of(up.node).onClick(_ -> stepNumber(1));
			Interaction.of(down.node).onClick(_ -> stepNumber(-1));
			steppers = [new Div({classes: ["steppers"]}, [up, down])];
		}
		var field = new TextField({
			value: text,
			type: type,
			placeholder: props.placeholder,
			disabled: props.disabled,
			onInput: v -> {
				edited = true;
				if (props.onInput != null)
					props.onInput(v);
			}
		}, steppers);
		var e = editing = field.editing;
		interaction = e.interaction;
		if (type == "number") {
			e.accept = typed -> ~/[^0-9.eE+-]/g.replace(typed, "");
			e.onKey = k -> switch k.key {
				case Named(ArrowUp):
					stepNumber(1);
					true;
				case Named(ArrowDown):
					stepNumber(-1);
					true;
				case _: false;
			}
		} else if (type == "search") {
			// Escape empties a search, and gives up focus only when it is empty already.
			e.onKey = k -> if (k.key.match(Named(Escape)) && text.get() != "") {
				text.set("");
				if (props.onInput != null)
					props.onInput("");
				true;
			} else false;
		}
		if (props.maxlength != null) {
			// No more than its maxlength typed or pasted: what is inserted is cut to the room left beside the selection.
			var limit = props.maxlength;
			var before = e.accept;
			e.accept = typed -> {
				var t = before == null ? typed : before(typed);
				var r = e.selectionRange();
				var room = limit - (text.get().length - (r.to - r.from));
				room <= 0 ? "" : t.length > room ? t.substr(0, room) : t;
			}
		}
		var identity = ashui.css.Identity.of(field.tree, field.node.id);
		if (props.id != null)
			identity.setId(props.id);
		if (props.name != null)
			identity.setAttribute("name", props.name);
		return field;
	}

	/** A number's or a range's value: `valueAsNumber`, else `value` read as a number, else `initial`. **/
	function numberState(initial:Float):Signal<Float> {
		switch props.valueAsNumber {
			case Bound(s): return s;
			case Const(v): return Signal.make(v);
			case Derived(c):
				var s = Signal.make(c.get());
				new Watch(() -> c.get(), v -> s.set(v));
				return s;
			case null:
		}
		var parsed = parseNumber(constValue() == null ? "" : constValue());
		return Signal.make(Math.isNaN(parsed) ? initial : parsed);
	}

	/** Moves a number by `by` steps from where it is, or from nothing, within its bounds. **/
	function stepNumber(by:Int):Void {
		if (interaction.disabled.get())
			return;
		var n = valueAsNumber;
		var step = props.step != null && props.step > 0 ? props.step : 1;
		var from = Math.isNaN(n.get()) ? (props.min != null ? props.min : 0) - (by > 0 ? step : -step) : n.get();
		var v = snap(from + by * step, props.min, props.max, step);
		if (!same(v, n.get())) {
			n.set(v);
			if (props.onInput != null)
				props.onInput(formatNumber(v));
		}
	}

	/** A range: a slider, its `.fill` and `.rest` either side of its `.thumb`, grown in proportion to the value. **/
	function range():Element {
		var vertical = props.orientation == "vertical";
		if (props.orientation != null && props.orientation != "horizontal" && !vertical)
			throw 'input: orientation is horizontal or vertical';
		var min = props.min != null ? props.min : 0.0;
		var max = props.max != null ? props.max : 100.0;
		if (max < min)
			max = min;
		var step = props.step != null && props.step > 0 ? props.step : 1.0;
		var n = valueAsNumber = numberState(snap(min + (max - min) / 2, min, max, step));
		var fraction = Computed.make(() -> {
			var v = n.get();
			(max > min && !Math.isNaN(v) ? Math.max(0, Math.min(1, (v - min) / (max - min))) : 0.0);
		});
		var fill = new Div({classes: ["fill"]});
		var thumb = new Div({classes: ["thumb"]});
		var rest = new Div({classes: ["rest"]});
		// Grown in proportion, the two together taking all the room the thumb leaves.
		fill.node.set(Prop.FlexGrow, Computed.make(() -> (fraction.get() : Single)));
		rest.node.set(Prop.FlexGrow, Computed.make(() -> (1 - fraction.get() : Single)));
		var parts:Array<Element> = [fill, thumb, rest];
		var box = new Div({tag: "input", id: props.id}, parts.concat(children));
		var identity = ashui.css.Identity.of(box.tree, box.node.id);
		identity.setAttribute("type", "range");
		identity.setAttribute("data-orientation", vertical ? "vertical" : "horizontal");
		if (props.name != null)
			identity.setAttribute("name", props.name);
		interaction = Interaction.of(box.node).setFocusable(true);
		if (props.disabled != null)
			interaction.setDisabled(props.disabled);
		var tree = box.tree;
		function set(v:Float) {
			v = snap(v, min, max, step);
			if (same(v, n.get()))
				return;
			n.set(v);
			if (props.onInput != null)
				props.onInput(formatNumber(v));
		}
		// The thumb's centre travels along the axis, with vertical values increasing upward.
		function seek(x:Float, y:Float) {
			var b = tree.getBounds(box.node), t = tree.getBounds(thumb.node);
			if (b == null || t == null)
				return;
			var travel = vertical ? b.height - t.height : b.width - t.width;
			var along = vertical ? b.y + b.height - y - t.height / 2 : x - b.x - t.width / 2;
			set(min + (travel > 0 ? along / travel : 0) * (max - min));
		}
		// A drag follows the pointer until the button comes up, wherever the pointer goes.
		var drag:Null<LayoutTree->Void> = null;
		function stopDrag() {
			if (drag != null)
				Pointer.hooks.remove(drag);
			drag = null;
		}
		interaction.onPointerDown(p -> {
			seek(p.x, p.y);
			stopDrag();
			drag = t -> if (t == tree) {
				var at = Pointer.at(tree);
				if (at.pressed) seek(at.x, at.y) else stopDrag();
			}
			Pointer.hooks.push(drag);
		});
		Owner.onCleanup(stopDrag);
		interaction.onKeyDown(e -> {
			var page = Math.max(step, (max - min) / 10);
			var v = n.get();
			switch e.key {
				case Named(ArrowRight) | Named(ArrowUp): set(v + step);
				case Named(ArrowLeft) | Named(ArrowDown): set(v - step);
				case Named(PageUp): set(v + page);
				case Named(PageDown): set(v - page);
				case Named(Home): set(min);
				case Named(End): set(max);
				case _: return;
			}
			e.preventDefault();
		});
		return box;
	}

	/** `v` on the grid of `step` from `min` (or 0), within `min` and `max` where given, rounded to the step's decimals. **/
	static function snap(v:Float, min:Null<Float>, max:Null<Float>, step:Float):Float {
		if (Math.isNaN(v))
			return v;
		var base = min != null ? min : 0.0;
		var places = decimals(step) + decimals(base);
		var scale = Math.pow(10, places);
		inline function grid(x:Float)
			return Math.round((base + x * step) * scale) / scale;
		v = grid(Math.round((v - base) / step));
		if (max != null && v > max)
			v = grid(Math.floor((max - base) / step));
		if (min != null && v < min)
			v = min;
		return v;
	}

	static function decimals(x:Float):Int {
		var s = Std.string(x);
		var dot = s.indexOf(".");
		return dot < 0 || s.indexOf("e") >= 0 ? 0 : s.length - dot - 1;
	}

	/** `s` as a number, as HTML reads one: NaN when it is not one, or empty. **/
	static function parseNumber(s:String):Float
		return ~/^[+-]?([0-9]+\.?[0-9]*|\.[0-9]+)([eE][+-]?[0-9]+)?$/.match(StringTools.trim(s)) ? Std.parseFloat(StringTools.trim(s)) : Math.NaN;

	static function formatNumber(v:Float):String
		return Math.isNaN(v) ? "" : Std.string(v);

	static inline function same(a:Float, b:Float):Bool
		return a == b || (Math.isNaN(a) && Math.isNaN(b));

	static var upMark:Null<ashui.svg.SvgDocument> = null;
	static var downMark:Null<ashui.svg.SvgDocument> = null;

	static function chevron(up:Bool):ashui.svg.SvgDocument {
		if (upMark == null) {
			upMark = ashui.svg.SvgDocument.of(<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"><path d="M6 15l6-6 6 6"/></svg>);
			downMark = ashui.svg.SvgDocument.of(<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"><path d="M6 9l6 6 6-6"/></svg>);
		}
		return up ? upMark : downMark;
	}

	/** Checks or flips it, as a click, Space or its label does, or focuses any other type; nothing while it is disabled. **/
	public function activate():Void {
		if (interaction.disabled.get())
			return;
		var type = props.type == null ? "text" : props.type.toLowerCase();
		if (type != "checkbox" && type != "radio") {
			ashui.input.Focus.set(interaction, false);
			return;
		}
		if (type == "checkbox") {
			interaction.indeterminate.set(false);
			state.set(!state.get());
		} else {
			if (isChecked())
				return;
			check();
		}
		touched.set(true);
		if (props.onChange != null)
			props.onChange(state.get());
	}

	/** Whether it is checked now: a grouped radio while its group holds its value, read now rather than when `state` catches up. **/
	public function isChecked():Bool
		return props.group != null && props.type != null && props.type.toLowerCase() == "radio" ? props.group.get() == constValue() : state.get();

	/** Checks this radio: its group takes its value, or the others of its name uncheck. **/
	function check():Void {
		if (props.group != null) {
			props.group.set(constValue());
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
