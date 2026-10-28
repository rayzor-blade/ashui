package ashui.layout;

import ashui.core.Utf8;
import ashui.core.externs.BlincNative;
import ashui.layout.IntoReactive;
import ashui.layout.PropertyId;
import ashui.reactive.Guard;
import ashui.types.IValue;

/**
	A handle to a native node in a `LayoutTree`. Each element exposes its node
	through `Element.node`. Create a node directly with `LayoutTree.createNode`.
	Nodes represent layout boxes or text runs (`TextNode`).

	Use `set(Prop.X, value)` to set a property. Values can be constants,
	signals or computeds. See `IntoReactive`.
**/
class Node {
	// How a router reads its arguments: the constant, the signal or the computed.
	static inline var KIND_CONST = 0;
	static inline var KIND_SIGNAL = 1;
	static inline var KIND_COMPUTED = 2;

	/** The node's id in its tree, made natively; what the tree's functions take. **/
	public var id(default, null):haxe.Int64;

	/** The tree that made this node. **/
	public var tree(default, null):Null<LayoutTree>;

	/** The effective display binding, retained for table slot visibility (471d54e); null means native Flex. **/
	@:noCompletion public var displayValue(default, null):Null<IntoReactive<ashui.types.Style.Display>>;

	/** Only display writes notify these subscribers; signal changes use the existing reactive graph. **/
	@:noCompletion public static final displayHooks:Array<Node->Void> = [];

	function recordDisplay(value:Null<IntoReactive<ashui.types.Style.Display>>):Void {
		displayValue = value;
		for (hook in displayHooks)
			hook(this);
	}

	/** What animates when a property it covers is set again or its value changes. **/
	public var transition(default, set):Null<ashui.animation.Transition>;

	var tweens:Null<FieldTable<ashui.animation.Tweened<Dynamic>>>;

	function set_transition(value:Null<ashui.animation.Transition>) {
		ownTransition = true;
		transition = value;
		retween();
		return value;
	}

	/**
		Properties bound to a signal or computed before any transition covered
		them, by property: a transition arriving later, as a stylesheet's does
		after an element is built, moves their later changes too.
	**/
	var reactives:Null<FieldTable<Dynamic>> = null;

	/**
		Constants bound with no tween, by property, for properties that can
		move: a transition arriving later moves the next change from here.
	**/
	var settled:Null<FieldTable<Dynamic>> = null;

	/** Puts each reactive binding the transition now covers behind a tween, from where it is. **/
	function retween():Void {
		if (transition == null || reactives == null)
			return;
		var i = 0;
		while (i < reactives.length) {
			var key = reactives.keyAt(i), reactive = reactives.valueAt(i);
			var prop:PropertyId = key;
			if (!transition.covers(prop) || (tweens != null && tweens.exists(key))) {
				i++;
				continue;
			}
			var tween = ashui.animation.Tweened.bind(this, prop, transition.forProperty(prop), reactive);
			if (tween != null) {
				if (tweens == null)
					tweens = new FieldTable();
				tweens.set(key, tween);
				reactives.remove(key);
			} else
				i++;
		}
	}

	/** Whether the node's own code set its transition, which a stylesheet's then leaves alone. **/
	var ownTransition = false;

	/** The key a stylesheet's transition is unset by, beside the property fields. **/
	public static inline var TRANSITION = 2000;

	/** A stylesheet's transition, set unless the node's own code set one; true if set. **/
	@:allow(ashui.css)
	function styleTransition(value:Null<ashui.animation.Transition>):Bool {
		if (ownTransition)
			return false;
		transition = value;
		ownTransition = false;
		if (value != null) {
			if (styled == null)
				styled = new FieldSet();
			styled.add(TRANSITION);
		}
		return true;
	}

	public function new(id:haxe.Int64) {
		this.id = id;
	}

	/**
		Sets a property or binds it to a signal or computed. `LayoutTree.flush` applies queued writes.
		If a transition covers this property, changes after its initial value animate over that transition.
	**/
	public function set<T>(prop:Prop<T>, reactive:IntoReactive<T>):Void {
		if (own == null)
			own = new FieldSet();
		own.add(field(prop, isCornerShape(reactive)));
		apply(prop, reactive);
	}

	/**
		`set` without claiming the property: how transitions and stylesheets
		write. `fresh` is a stylesheet's first value for the field: on a
		restyle after the first, a tween made for it starts from the
		property's initial value, as a CSS transition does.
	**/
	function apply<T>(prop:Prop<T>, reactive:IntoReactive<T>, fresh = false):Void {
		var key:PropertyId = prop;
		if (transition != null && transition.covers(key) && !isCornerShape(reactive)) {
			if (tweens == null)
				tweens = new FieldTable();
			var timing = transition.forProperty(key);
			var tween = tweens.get(key);
			if (tween != null) {
				tween.retime(timing);
				tween.follow(cast reactive);
				return;
			}
			var from = fresh && restyling ? ashui.animation.Tweened.initial(key) : settled != null ? settled.get(key) : null;
			// A constant written for the first time is applied plain, and noted in `settled`: the tween is made when the property
			// next changes, from this value, so a property that never moves costs no tween.
			if (!(fresh && restyling) && ashui.animation.Tweened.initial(key) != null) {
				switch (reactive : ReactiveType<T>) {
					case Const(v) if (from == null || ashui.animation.Tweened.equal(key, from, v)):
						writePlain(key, prop, reactive);
						return;
					case _:
				}
			}
			tween = ashui.animation.Tweened.bind(this, key, timing, cast reactive, from);
			if (tween != null) {
				tweens.set(key, tween);
				if (settled != null)
					settled.remove(key);
				return;
			}
			traceSnap(key, from, reactive);
		}
		// Remembered while it follows a signal or computed, for a transition that arrives later.
		switch (reactive : ReactiveType<T>) {
			case Bound(_) | Derived(_):
				if (reactives == null)
					reactives = new FieldTable();
				reactives.set(key, reactive);
				if (settled != null)
					settled.remove(key);
			case Const(v):
				if (reactives != null)
					reactives.remove(key);
				if (ashui.animation.Tweened.initial(key) != null) {
					if (settled == null)
						settled = new FieldTable();
					settled.set(key, v);
				}
		}
		bind(prop, reactive);
	}

	/** A constant bound with no tween, kept in `settled` for a transition's later move from it. **/
	function writePlain<T>(key:PropertyId, prop:Prop<T>, reactive:IntoReactive<T>):Void {
		switch (reactive : ReactiveType<T>) {
			case Const(v):
				if (reactives != null)
					reactives.remove(key);
				if (settled == null)
					settled = new FieldTable();
				settled.set(key, v);
			case _:
		}
		bind(prop, reactive);
	}

	/**
		Properties the node's own code set, by `field`: its classes, its
		style, its attributes and calls to `set`. A stylesheet never writes
		these, as an element's own styles win over its stylesheet's in
		Tailwind's layers. Null until one is set.
	**/
	var own:Null<FieldSet> = null;

	/** Properties a stylesheet set, by `field`, so one no rule sets any more can be unset. **/
	var styled:Null<FieldSet> = null;

	/** The corner shape's key: it shares the corner radius's property but is a field of its own. **/
	public static inline var CORNER_SHAPE = 1003;

	/**
		The field `prop` writes, as a key: two properties that write the same
		field share one, `Width` and `WidthPercent`, `AccentColor` and
		`OutlineColor`, and a corner shape has its own.
	**/
	public static function field(prop:PropertyId, cornerShape = false):Int {
		var raw:Int = prop;
		if (cornerShape)
			return CORNER_SHAPE;
		return switch raw {
			case 104 | 105 | 106 | 107: raw - 61;
			case 108 | 109 | 110 | 111: raw - 61;
			case 112 | 113 | 114 | 115: raw - 82;
			case 116 | 117: raw - 65;
			case 53 | 54 | 55 | 56 | 57 | 58: raw - 43;
			case 59: 26;
			case 66: 9;
			case _: raw;
		}
	}

	/** The shorthand a field is part of, which owning covers it: `Padding` for `PaddingTop`. **/
	static function shorthand(key:Int):Int {
		return switch key {
			case 99 | 100: 28;
			case 43 | 44 | 45 | 46: 16;
			case 47 | 48 | 49 | 50: 17;
			case 51 | 52: 18;
			case 60 | 61 | 62 | 63: 2;
			case 67 | 68 | 69 | 70: 1;
			case 76 | 77 | 78 | 79 | 80 | 81 | 82 | 83 | 84: 8;
			case _: -1;
		}
	}

	/** Whether the node's own code set the field `key`, or a shorthand covering it. **/
	public function owns(key:Int):Bool
		return own != null && (own.exists(key) || own.exists(shorthand(key)));

	/** A stylesheet's value for `prop`, written unless the node owns its field; true if written. **/
	@:allow(ashui.css)
	function style<T>(prop:Prop<T>, value:T, cornerShape = false):Bool {
		var key = field(prop, cornerShape);
		if (owns(key))
			return false;
		if (styled == null)
			styled = new FieldSet();
		var fresh = styled.add(key);
		// Within a restyle, the last write to each field is the one made, so a
		// shorthand then a longhand for the same field moves once, not twice.
		if (batch != null && !immediate) {
			batch.set(key, () -> apply(prop, Const(value), fresh));
			return true;
		}
		// An animation's frames are each where the property is, not somewhere to move to.
		if (immediate) {
			var id:PropertyId = prop;
			var tween = tweens == null ? null : tweens.get(id);
			if (tween != null)
				@:privateAccess tween.jump(value);
			else
				bind(prop, Const(value));
		} else
			apply(prop, Const(value), fresh);
		return true;
	}

	/** A stylesheet's writes held while the cascade restyles this node, the last per field. **/
	var batch:Null<StyleBatch> = null;

	/** Runs `writes`, the stylesheet's writes to this node, then makes the last write to each field. **/
	@:allow(ashui.css)
	function styleAll(writes:Void->Void):Void {
		var outer = batch, held = StyleBatch.take();
		batch = held;
		try
			writes()
		catch (e:haxe.Exception) {
			batch = outer;
			held.discard();
			throw e;
		}
		batch = outer;
		held.run();
	}

	/** A CSS value such as `z-index: auto` explicitly restores the native initial value. **/
	@:allow(ashui.css)
	function styleInitial(prop:PropertyId):Void {
		var key = field(prop);
		if (owns(key))
			return;
		if (styled == null)
			styled = new FieldSet();
		styled.add(key);
		var reset = () -> {
			if (key == PropertyId.Display)
				recordDisplay(null);
			BlincNative.blinc_unset(id, key);
		};
		if (batch != null && !immediate)
			batch.set(key, reset);
		else
			reset();
	}

	/** While true, the cascade restyles an element it styled before: a field it gives a value for the first time moves from its initial value. **/
	@:allow(ashui.css)
	static var restyling = false;

	/** While true, a stylesheet's writes take effect at once, past any transition: an animation's frames. **/
	@:allow(ashui.css)
	static var immediate = false;

	/** Takes back a stylesheet's value for the field `key`: the field returns to a new node's, unless the node owns it. **/
	@:allow(ashui.css)
	function unstyle(key:Int):Void {
		if (styled == null || !styled.remove(key))
			return;
		if (key == TRANSITION) {
			if (!ownTransition) {
				transition = null;
				ownTransition = false;
			}
			return;
		}
		if (owns(key))
			return;
		if (key == PropertyId.Overflow || key == PropertyId.OverflowX || key == PropertyId.OverflowY)
			ashui.input.Scroll.configure(this, key, false);
		// Under a transition that covers it, it moves back to its initial value rather than jumping there.
		var prop:PropertyId = key;
		var tween = tweens == null ? null : tweens.get(prop);
		var initial = ashui.animation.Tweened.initial(prop);
		if (initial != null && transition != null && transition.covers(prop)) {
			if (tween != null) {
				tween.follow(Const(initial));
				return;
			}
			var at = settled != null ? settled.get(key) : null;
			tween = at == null ? null : ashui.animation.Tweened.bind(this, prop, transition.forProperty(prop), Const(initial), at);
			if (tween != null) {
				if (tweens == null)
					tweens = new FieldTable();
				tweens.set(key, tween);
				settled.remove(key);
				return;
			}
			traceSnap(prop, at, Const(initial));
		}
		// Forgotten, so a later value starts a tween from where the property is, not from where this one left it.
		if (tween != null)
			tweens.remove(prop);
		if (settled != null)
			settled.remove(key);
		if (key == PropertyId.Display)
			recordDisplay(null);
		BlincNative.blinc_unset(id, key);
	}

	/** Records, while a motion trace runs, a change a transition covers that took effect with no tween. **/
	function traceSnap<T>(prop:PropertyId, from:Null<Dynamic>, to:IntoReactive<T>):Void {
		if (ashui.debug.MotionTrace.current == null || transition == null)
			return;
		var timing = transition.forProperty(prop);
		var t = ashui.debug.MotionTrace.begin(Transition, tree, id, ashui.debug.PropertyNames.name(prop), ashui.animation.Tweened.describe(prop, from),
			ashui.animation.Tweened.describe(prop, ashui.animation.Tweened.read(cast to)), timing.delay(), timing.seconds(), timing.curve());
		if (t != null)
			t.finish(Snapped);
	}

	/** A corner shape shares the radius's property but switches at once. **/
	static function isCornerShape<T>(reactive:IntoReactive<T>):Bool {
		return switch (reactive : ReactiveType<T>) {
			case Const(v): Std.isOfType(v, ashui.types.CornerShape);
			case Bound(s): Std.isOfType(s.get(), ashui.types.CornerShape);
			case Derived(c): Std.isOfType(c.get(), ashui.types.CornerShape);
		}
	}

	/** `prop` bound to `reactive` directly, whatever the transition. **/
	@:allow(ashui.animation.Tweened)
	function bind<T>(prop:PropertyId, reactive:IntoReactive<T>):Void {
		switch (prop.getDataType()) {
			case TypeF32:
				applyF32(prop, cast reactive);
			case TypeI32:
				applyI32(prop, cast reactive);
			case TypeBrush | TypeColor | TypeCornerRadius | TypeTransform | TypeShadow | TypeClipPath | TypeTextDecoration:
				applyValue(prop, cast reactive);
			case TypeString:
				applyString(prop, cast reactive);
		}
	}

	/** Binds a `Single` property. `set` calls this, and the others below, by the property's type. **/
	public function applyF32(prop:PropertyId, reactive:IntoReactive<Single>):Void {
		switch (reactive) {
			case Const(v):
				BlincNative.blinc_apply_f32(id, prop, KIND_CONST, v, null, null);
			case Bound(s):
				BlincNative.blinc_apply_f32(id, prop, KIND_SIGNAL, 0, s.ptr, null);
			case Derived(c):
				BlincNative.blinc_apply_f32(id, prop, KIND_COMPUTED, 0, null, c.ptr);
		}
		Guard.check();
		ashui.core.Work.notify();
	}

	/** Binds an `Int` property, enums included. **/
	public function applyI32(prop:PropertyId, reactive:IntoReactive<Int>):Void {
		if (prop == PropertyId.Display)
			recordDisplay(cast reactive);
		if (tree != null && (prop == PropertyId.Overflow || prop == PropertyId.OverflowX || prop == PropertyId.OverflowY))
			ashui.input.Scroll.bindOverflow(this, prop, reactive);
		switch (reactive) {
			case Const(v):
				BlincNative.blinc_apply_i32(id, prop, KIND_CONST, v, null, null);
			case Bound(s):
				BlincNative.blinc_apply_i32(id, prop, KIND_SIGNAL, 0, s.ptr, null);
			case Derived(c):
				BlincNative.blinc_apply_i32(id, prop, KIND_COMPUTED, 0, null, c.ptr);
		}
		Guard.check();
		ashui.core.Work.notify();
	}

	/** Binds a style-value property: brushes, colours, radii, transforms, shadows and clip paths. **/
	public function applyValue(prop:PropertyId, reactive:IntoReactive<IValue>):Void {
		switch (reactive) {
			case Const(v):
				BlincNative.blinc_apply_value(id, prop, KIND_CONST, v == null ? null : v.ptr, null, null);
			case Bound(s):
				BlincNative.blinc_apply_value(id, prop, KIND_SIGNAL, null, s.ptr, null);
			case Derived(c):
				BlincNative.blinc_apply_value(id, prop, KIND_COMPUTED, null, null, c.ptr);
		}
		Guard.check();
		ashui.core.Work.notify();
	}

	/** Binds a `String` property. **/
	public function applyString(prop:PropertyId, reactive:IntoReactive<String>):Void {
		switch (reactive) {
			case Const(v):
				BlincNative.blinc_apply_string(id, prop, KIND_CONST, Utf8.encode(v), null, null);
			case Bound(s):
				BlincNative.blinc_apply_string(id, prop, KIND_SIGNAL, null, s.ptr, null);
			case Derived(c):
				BlincNative.blinc_apply_string(id, prop, KIND_COMPUTED, null, null, c.ptr);
		}
		Guard.check();
		ashui.core.Work.notify();
	}
}

/**
	The writes of one restyle, the last to each field, made in the order the
	fields were first written. Batches are pooled, so a restyle makes no table.
**/
private class StyleBatch {
	static final pool:Array<StyleBatch> = [];

	final keys:Array<Int> = [];
	final writes:Array<Void->Void> = [];

	/** Where in `keys` each field is, plus one; zero for a field not written. **/
	final at:Array<Int> = [];

	function new() {}

	public static function take():StyleBatch
		return pool.length > 0 ? pool.pop() : new StyleBatch();

	public function set(key:Int, write:Void->Void):Void {
		while (at.length <= key)
			at.push(0);
		var held = at[key];
		if (held == 0) {
			keys.push(key);
			writes.push(write);
			at[key] = keys.length;
		} else
			writes[held - 1] = write;
	}

	/** Makes each held write, then returns the batch to the pool. **/
	public function run():Void {
		var i = 0;
		try
			while (i < writes.length)
				writes[i++]()
		catch (e:haxe.Exception) {
			discard();
			throw e;
		}
		discard();
	}

	/** Forgets the writes and returns the batch to the pool. **/
	public function discard():Void {
		for (key in keys)
			at[key] = 0;
		keys.resize(0);
		writes.resize(0);
		pool.push(this);
	}
}
