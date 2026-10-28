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
	/** Input type: `checkbox`, `radio`, `range`, `number`, `text` (default), `password`, `search`, `email`, `tel`, or `url`. **/
	?type:String,

	/** Checked state. A supplied signal is read and updated; a constant sets the initial state. **/
	?checked:IntoReactive<Bool>,

	/** Shows a checkbox in the indeterminate state until activated. Exposes CSS `:indeterminate`. **/
	?indeterminate:IntoReactive<Bool>,

	/**
		The input value as text. Text and number inputs read and write a supplied
		signal. Radios use this as their selected group value. Ranges use it as
		the initial value unless `valueAsNumber` is supplied.
	**/
	?value:IntoReactive<String>,

	/** Numeric value for number and range inputs. Updates a supplied signal; an empty number input has value NaN. **/
	?valueAsNumber:IntoReactive<Float>,

	/** Lower bound for number and range inputs. Ranges default to 0–100 with a step of 1. **/
	?min:Float,
	?max:Float,
	?step:Float,

	/** Range axis: `horizontal` (default) or `vertical`. Vertical values increase from bottom to top. **/
	?orientation:String,

	/** Placeholder for an empty text or number input. Exposes CSS `:placeholder-shown`. **/
	?placeholder:String,

	/** Requires a value, a checked checkbox, or a selected radio before form submission. **/
	?required:Bool,

	/** Regular expression that must match the entire text value. **/
	?pattern:String,

	/** Minimum text length. `maxlength` limits typed and pasted text. **/
	?minlength:Int,
	?maxlength:Int,

	/**
		Shared selected value for a radio group. Selecting a radio updates this
		signal. Radios sharing the signal also form one keyboard navigation group.
	**/
	?group:Signal<String>,

	/** Form field name. Radios with the same name in one tree form a group when no explicit `group` is supplied. **/
	?name:String,

	?disabled:IntoReactive<Bool>,

	/** Element ID used by CSS selectors and a label `for` attribute. **/
	?id:String,

	/** Receives the new checked state after checkbox or radio activation by pointer, Space, or label. **/
	?onChange:Bool->Void,

	/** Receives the text value after an edit, step, or range drag. **/
	?onInput:String->Void,

	/** Runs when form submission or `checkValidity()` finds the control invalid. **/
	?onInvalid:Void->Void,

	/**
		Shows password characters instead of dots while true. Copying remains
		disabled. This attribute extends the HTML password input behavior.
	**/
	?reveal:IntoReactive<Bool>
}

/**
	The built-in HTML-style input control. `type` selects its behavior:

	- `checkbox`: toggles on click, label activation or Space release.
	- `radio`: selects on the same actions. Arrow keys move within the group.
	- Text types: use `TextField`. Passwords hide text and prevent copying;
	  Escape clears a search input. Children can add icons or reveal buttons.
	- `number`: supports numeric entry and stepping within `min` and `max`.
	- `range`: supports pointer dragging, arrows, Home and End. Page Up and
	  Page Down move by one tenth of the range.

	Disabled controls reject input. Validation follows the relevant HTML
	constraints: `required`, `pattern`, text length, email/URL format,
	numeric bounds and step. CSS validity pseudo-classes reflect the result.
	User-validity states apply after editing and leaving the control, or after
	form submission.

	Use `validity` and `validationMessage` to inspect validation. Call
	`checkValidity` or `reportValidity` to validate, and `setCustomValidity`
	to add an application error. Invalid checks call `onInvalid`.
	`reset` restores the initial value.

	The user-agent stylesheet styles `input[type="..."]` and its state
	pseudo-classes. Range parts are `.fill`, `.thumb` and `.rest`.
	Number steppers use `.steppers`, `.step-up` and `.step-down`.
**/
class Input extends Component<InputProps> implements FormControl {
	/** Input lookup used by labels. **/
	static final byNode = new Map<String, Input>();

	/** Radios registered per tree. Resolve document order through `tree.order()`. **/
	static final radios = new haxe.ds.ObjectMap<LayoutTree, Array<Input>>();

	static var checkMark:Null<ashui.svg.SvgDocument> = null;
	static var dashMark:Null<ashui.svg.SvgDocument> = null;

	/** Current checked state. Uses the supplied signal when available. **/
	public var state(default, null):Signal<Bool>;

	/** Current text for text and number inputs. Uses the caller `value` signal when supplied. **/
	public var value(default, null):Null<Signal<String>> = null;

	/** Current numeric value for number and range inputs. Uses the caller `valueAsNumber` signal when supplied. **/
	public var valueAsNumber(default, null):Null<Signal<Float>> = null;

	/** Caret, selection, and display state for text and number inputs. **/
	public var editing(default, null):Null<TextEditing> = null;

	var interaction:Interaction;
	var setRange:Null<Float->Void>;
	var dragRange:Null<(Float, Float) -> Void>;

	/** Additional limit applied before a range edit is published. Used by composed range controls (095fab4). **/
	public var rangeLimit:Null<Float->Float>;

	/** Tracks whether editing and blur, or form submission, have enabled user-validity styles. **/
	final touched = Signal.make(false);

	/** Constraint results and custom error message, shared by validity methods and CSS states. **/
	var validityOf:FormStates.Validity;

	/** Whether the user has edited the value since focus began. **/
	var edited = false;

	/** Initial values restored by `reset()`. **/
	var initial:{text:Null<String>, checked:Bool, group:Null<String>} = {text: null, checked: false, group: null};

	var initialRange:Null<Float>;

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

	/** Updates CSS form states from the current value and constraints. **/
	function constrain(type:String):Void {
		var i = interaction;
		initial = {text: value != null ? value.get() : null, checked: state.get(), group: props.group != null ? props.group.get() : null};
		initialRange = type == "range" ? valueAsNumber.get() : null;
		validityOf = new FormStates.Validity(problems);
		FormStates.keep(i, props.required == true, validityOf, touched);
		if (value != null && props.placeholder != null) {
			var text = value;
			new Watch(() -> text.get() == "", empty -> i.formState("placeholder-shown").set(empty));
		}
		// Leaving it after an edit touches it.
		i.onBlur(_ -> if (edited) touched.set(true));
		i.onFocus(_ -> edited = false);
	}

	/** Returns the current validation failures and their messages. **/
	function problems():Array<FormStates.ValidityProblem> {
		var type = props.type == null ? "text" : props.type.toLowerCase();
		inline function one(flag:FormStates.ValidityFlag, message:String):Array<FormStates.ValidityProblem>
			return [{flag: flag, message: message}];
		switch type {
			case "checkbox":
				return props.required == true && !state.get() ? one(ValueMissing, "Please tick this box if you want to proceed.") : [];
			case "radio":
				if (props.required != true)
					return [];
				var chosen = props.group != null ? props.group.get() != null && props.group.get() != "" : Lambda.exists(set(), r -> r.state.get());
				return chosen ? [] : one(ValueMissing, "Please select one of these options.");
			case "range":
				return [];
			case _:
		}
		var v = value == null ? "" : value.get();
		// An empty value breaks only `required`, as a browser checks.
		if (v == "")
			return props.required == true ? one(ValueMissing, "Please fill in this field.") : [];
		var out:Array<FormStates.ValidityProblem> = [];
		if (type == "number") {
			var n = parseNumber(v);
			if (Math.isNaN(n))
				return one(BadInput, "Please enter a number.");
			if (props.min != null && n < props.min)
				out.push({flag: RangeUnderflow, message: 'Value must be greater than or equal to ${formatNumber(props.min)}.'});
			if (props.max != null && n > props.max)
				out.push({flag: RangeOverflow, message: 'Value must be less than or equal to ${formatNumber(props.max)}.'});
			if (props.step != null && props.step > 0 && !same(snap(n, props.min, null, props.step), n))
				out.push({flag: StepMismatch, message: "Please enter a valid value."});
			return out;
		}
		if (type == "email" && !~/^[^\s@]+@[^\s@.]+(\.[^\s@.]+)*$/.match(v))
			out.push({flag: TypeMismatch, message: v.indexOf("@") < 0 ? 'Please include an "@" in the email address.' : "Please enter an email address."});
		if (type == "url" && !~/^[a-zA-Z][a-zA-Z0-9+.-]*:[^\s]+$/.match(v))
			out.push({flag: TypeMismatch, message: "Please enter a URL."});
		if (props.pattern != null && !(try new EReg("^(?:" + props.pattern + ")$", "u").match(v) catch (_:Dynamic) true))
			out.push({flag: PatternMismatch, message: "Please match the requested format."});
		// As a browser, too short only once the user has edited it.
		return out.concat(FormStates.lengthProblems(v, props.minlength, props.maxlength, touched.get()));
	}

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

	/** Marks the control touched so user-validity styles can appear. **/
	public function touch():Void
		touched.set(true);

	/** Restores the initial value and checked state, then clears touched state. **/
	public function reset():Void {
		if (value != null && initial.text != null)
			value.set(initial.text);
		if (initialRange != null && valueAsNumber != null)
			valueAsNumber.set(initialRange);
		if (props.group != null && initial.group != null)
			props.group.set(initial.group);
		else
			state.set(initial.checked);
		touched.set(false);
	}

	/** Returns the form field name, or null when unnamed. **/
	public function name():Null<String>
		return props.name;

	/** Returns the value to submit, or null to omit the control. Checkboxes and radios submit only while checked. **/
	public function formValue():Null<String> {
		var type = props.type == null ? "text" : props.type.toLowerCase();
		return switch type {
			case "checkbox": state.get() ? (constValue() != null ? constValue() : "on") : null;
			case "radio": isChecked() ? constValue() : null;
			case "range": valueAsNumber != null ? formatNumber(valueAsNumber.get()) : null;
			case _: value != null ? value.get() : null;
		}
	}

	/** Returns whether Enter submits the form for this input type. **/
	public function submitsOnEnter():Bool {
		var type = props.type == null ? "text" : props.type.toLowerCase();
		return type == "number" || TEXT_TYPES.indexOf(type) >= 0;
	}

	/** Moves focus to this control. **/
	public function focus():Void
		ashui.input.Focus.set(interaction, true);

	static final TEXT_TYPES = ["text", "password", "search", "email", "tel", "url"];

	/** Returns the constant value of a radio or checkbox, or null for other input types. **/
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
			case Const(v):
				interaction.setIndeterminate(v);
			case Bound(s):
				new Watch(() -> s.get(), v -> interaction.setIndeterminate(v));
			case Derived(c):
				new Watch(() -> c.get(), v -> interaction.setIndeterminate(v));
		}

		if (type == "checkbox") {
			if (checkMark == null) {
				checkMark = ashui.svg.SvgDocument.of(<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3.5" stroke-linecap="round" stroke-linejoin="round"><path d="M5 12l5 5L20 7"/></svg>);
				dashMark = ashui.svg.SvgDocument.of(<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3.5" stroke-linecap="round"><path d="M6 12h12"/></svg>);
			}
			var check = new Svg(checkMark);
			ashui.css.Identity.of(check.tree, check.node.id).setClasses(["check"]);
			var dash = new Svg(dashMark);
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

	/** Builds a `TextField` for text or number input, adding steppers for numbers. **/
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
			// External numeric writes take precedence over queued text from an earlier value.
			var lastNumber = n.get();
			// Partial text such as "1e" leaves the number unchanged.
			new Watch(() -> text.get(), t -> {
				if (t != text.get() || !same(n.get(), lastNumber))
					return;
				var v = parseNumber(t);
				if ((t == "" || !Math.isNaN(v)) && !same(v, n.get())) {
					lastNumber = v;
					n.set(v);
				}
			});
			new Watch(() -> n.get(), _ -> {
				var v = n.get();
				lastNumber = v;
				if (!same(parseNumber(text.get()), v))
					text.set(formatNumber(v));
			});
			var up = new Div({classes: ["step-up"]}, [new Svg(chevron(true))]);
			var down = new Div({classes: ["step-down"]}, [new Svg(chevron(false))]);
			Interaction.of(up.node).onClick(_ -> stepNumber(1));
			Interaction.of(down.node).onClick(_ -> stepNumber(-1));
			steppers = [new Div({classes: ["steppers"]}, [up, down])];
		}
		var field = new TextField({
			value: text,
			type: type,
			placeholder: props.placeholder,
			disabled: props.disabled,
			reveal: props.reveal,
			onInput: v -> {
				edited = true;
				if (props.onInput != null)
					props.onInput(v);
			}
		}, steppers.concat(children == null ? [] : children));
		var e = editing = field.editing;
		// TextEditing consumes Enter to avoid clicking the text field. Submit through its existing callback.
		e.onSubmit = _ -> {
			var form = Form.near(field.tree, field.node.id);
			if (form != null)
				form.requestSubmit(form.defaultSubmitter());
		};
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

	/** Resolves numeric state from `valueAsNumber`, then parsed `value`, then the initial value. **/
	function numberState(initial:Float):Signal<Float> {
		switch props.valueAsNumber {
			case Bound(s):
				return s;
			case Const(v):
				return Signal.make(v);
			case Derived(c):
				var s = Signal.make(c.get());
				new Watch(() -> c.get(), v -> s.set(v));
				return s;
			case null:
		}
		var parsed = parseNumber(constValue() == null ? "" : constValue());
		return Signal.make(Math.isNaN(parsed) ? initial : parsed);
	}

	/** Changes a number by `by` steps, clamped to its bounds. Also handles an empty value. **/
	public function stepNumber(by:Int):Void {
		if (valueAsNumber == null || by == 0 || interaction.disabled.get())
			return;
		var n = valueAsNumber;
		var step = props.step != null && props.step > 0 ? props.step : 1;
		var from = Math.isNaN(n.get()) ? (props.min != null ? props.min : 0) - (by > 0 ? step : -step) : n.get();
		if (setRange != null) {
			setRange(from + by * step);
			return;
		}
		var v = snap(from + by * step, props.min, props.max, step);
		if (!same(v, n.get())) {
			n.set(v);
			if (props.onInput != null)
				props.onInput(formatNumber(v));
		}
	}

	/**
		Starts a range drag at window coordinates. Composed controls can select
		and focus an endpoint, then delegate dragging here. Has no effect on
		other input types or disabled ranges (095fab4).
	**/
	public function beginRangeDrag(x:Float, y:Float):Void {
		if (dragRange != null && !interaction.disabled.get())
			dragRange(x, y);
	}

	/** Builds a range slider with `.fill`, `.thumb`, and `.rest` sized from the value. **/
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
			if (rangeLimit != null)
				v = snap(rangeLimit(v), min, max, step);
			if (same(v, n.get()))
				return;
			n.set(v);
			if (props.onInput != null)
				props.onInput(formatNumber(v));
		}
		setRange = set;
		// The thumb's centre travels along the axis, with vertical values increasing upward.
		function seek(x:Float, y:Float) {
			var b = tree.getBounds(box.node), t = tree.getBounds(thumb.node);
			if (b == null || t == null)
				return;
			var edges = tree.getBox(box.node);
			var start = vertical ? edges.border[2] + edges.padding[2] : edges.border[3] + edges.padding[3];
			var end = vertical ? edges.border[0] + edges.padding[0] : edges.border[1] + edges.padding[1];
			var travel = (vertical ? b.height - t.height : b.width - t.width) - start - end;
			var along = vertical ? b.y + b.height - start - y - t.height / 2 : x - b.x - start - t.width / 2;
			set(min + (travel > 0 ? along / travel : 0) * (max - min));
		}
		// The shared FSM owns active-only capture, including composed gauges (095fab4).
		var phase = new ashui.state.Machine<RangePhase, RangeEvent>(Idle, (s, e) -> switch [s, e] {
			case [Idle, Begin]: Dragging;
			case [Dragging, End]: Idle;
			case _: null;
		});
		identity.bindAttribute("data-state", phase.name());
		var drag:Null<LayoutTree->Void> = null;
		function stopDrag() {
			if (drag != null)
				Pointer.hooks.remove(drag);
			drag = null;
		}
		phase.onEnter(Dragging, _ -> {
			drag = t -> if (t == tree) {
				var at = Pointer.at(tree);
				if (at.pressed && !interaction.disabled.get())
					seek(at.x, at.y)
				else
					phase.send(End);
			}
			Pointer.hooks.push(drag);
		});
		phase.onExit(Dragging, _ -> stopDrag());
		dragRange = (x, y) -> {
			phase.send(End);
			seek(x, y);
			phase.send(Begin);
		};
		interaction.onPointerDown(p -> beginRangeDrag(p.x, p.y));
		new Watch(() -> interaction.disabled.get(), disabled -> if (disabled) phase.send(End));
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

	/** Snaps a number to `step` from `min` (or zero), clamps to supplied bounds, and rounds to the step precision. **/
	public static function constrainNumber(v:Float, ?min:Float, ?max:Float, step = 1.0):Float
		return snap(v, min, max, step > 0 ? step : 1);

	static function snap(v:Float, min:Null<Float>, max:Null<Float>, step:Float):Float {
		if (Math.isNaN(v))
			return v;
		var base = min != null ? min : 0.0;
		var places = decimals(step) + decimals(base);
		var scale = Math.pow(10, places);
		inline function grid(x:Float)
			return Math.round((base + x * step) * scale) / scale;
		v = grid(Math.round((v - base) / step));
		if (max != null && v > max) {
			var last = Math.floor((max - base) / step);
			// A subtraction such as 2.05 - 1.05 can fall just below 1.
			// Compare the rounded grid point rather than dropping a valid final step (095fab4).
			if (grid(last + 1) <= max)
				last++;
			v = grid(last);
		}
		if (min != null && v < min)
			v = min;
		return v;
	}

	static function decimals(x:Float):Int {
		var s = Std.string(x);
		var exponent = s.indexOf("e");
		var places = exponent < 0 ? 0 : Std.parseInt(s.substr(exponent + 1));
		var mantissa = exponent < 0 ? s : s.substr(0, exponent);
		var dot = mantissa.indexOf(".");
		return Std.int(Math.max(0, (dot < 0 ? 0 : mantissa.length - dot - 1) - places));
	}

	/** Parses a numeric input value. Returns NaN for empty or invalid text. **/
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

	/** Toggles a checkbox, selects a radio, or focuses another input type. Disabled controls ignore activation. **/
	public function activate():Void {
		if (interaction.disabled.get())
			return;
		var type = props.type == null ? "text" : props.type.toLowerCase();
		if (type != "checkbox" && type != "radio") {
			ashui.input.Focus.set(interaction, false);
			return;
		}
		if (type == "checkbox") {
			interaction.setIndeterminate(false);
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

	/** Returns the current checked state. Grouped radios read the group directly rather than waiting for the state signal. **/
	public function isChecked():Bool
		return props.group != null
			&& props.type != null
			&& props.type.toLowerCase() == "radio" ? props.group.get() == constValue() : state.get();

	/** Selects this radio and clears the other selection in its signal or named group. **/
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

	/** Returns the radio group in document order, using the explicit group or the shared name. **/
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
			var ia = order.get(haxe.Int64.toStr(a.node.id)),
				ib = order.get(haxe.Int64.toStr(b.node.id));
			(ia == null ? 0 : ia) - (ib == null ? 0 : ib);
		});
		return mine;
	}

	/** Selects and focuses the next (`1`) or previous (`-1`) enabled radio, wrapping at either end. **/
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

	/** Returns the input at a node in `tree`, or null when absent. **/
	public static function at(tree:LayoutTree, node:haxe.Int64):Null<Input>
		return byNode.get(haxe.Int64.toStr(node));
}

private enum RangePhase {
	Idle;
	Dragging;
}

private enum RangeEvent {
	Begin;
	End;
}
