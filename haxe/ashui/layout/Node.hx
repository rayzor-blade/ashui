package ashui.layout;

import ashui.core.Utf8;
import ashui.core.externs.BlincNative;
import ashui.layout.IntoReactive;
import ashui.layout.PropertyId;
import ashui.reactive.Guard;
import ashui.types.IValue;

/**
	A handle to one node of a `LayoutTree`: a box laid out with flexbox, or
	a run of text (`TextNode`). The node itself lives in the tree, natively;
	this object holds its `id`, and is how its properties are set. Every
	element owns one, as `Element.node`; make one directly with
	`LayoutTree.createNode`.

	Set a property with `set(Prop.X, value)`, the value a constant, a signal
	or a computed (see `IntoReactive`).
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

	/** What animates when a property it covers is set again or its value changes. **/
	public var transition(default, set):Null<ashui.animation.Transition>;

	var tweens:Null<Map<Int, ashui.animation.Tweened<Dynamic>>>;

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
	var reactives:Null<Map<Int, Dynamic>> = null;

	/** Puts each reactive binding the transition now covers behind a tween, from where it is. **/
	function retween():Void {
		if (transition == null || reactives == null)
			return;
		for (key => reactive in reactives) {
			var prop:PropertyId = key;
			if (!transition.covers(prop) || (tweens != null && tweens.exists(key)))
				continue;
			var tween = ashui.animation.Tweened.bind(this, prop, transition.forProperty(prop), reactive);
			if (tween != null) {
				if (tweens == null)
					tweens = new Map();
				tweens.set(key, tween);
				reactives.remove(key);
			}
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
				styled = new Map();
			styled.set(TRANSITION, true);
		}
		return true;
	}

	public function new(id:haxe.Int64) {
		this.id = id;
	}

	/**
		Binds `prop` to a constant, signal or computed. A binding applies the
		current value at once and every change after it; `LayoutTree.flush`
		makes them take effect. Under a `transition` that covers `prop`, each
		change after the first moves there over the transition's time.
	**/
	public function set<T>(prop:Prop<T>, reactive:IntoReactive<T>):Void {
		if (own == null)
			own = new Map();
		own.set(field(prop, isCornerShape(reactive)), true);
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
				tweens = new Map();
			var timing = transition.forProperty(key);
			var tween = tweens.get(key);
			if (tween != null) {
				tween.retime(timing);
				tween.follow(cast reactive);
				return;
			}
			var from = fresh && restyling ? ashui.animation.Tweened.initial(key) : null;
			tween = ashui.animation.Tweened.bind(this, key, timing, cast reactive, from);
			if (tween != null) {
				tweens.set(key, tween);
				return;
			}
		}
		// Remembered while it follows a signal or computed, for a transition that arrives later.
		switch (reactive : ReactiveType<T>) {
			case Bound(_) | Derived(_):
				if (reactives == null)
					reactives = new Map();
				reactives.set(key, reactive);
			case Const(_):
				if (reactives != null)
					reactives.remove(key);
		}
		bind(prop, reactive);
	}

	/**
		Properties the node's own code set, by `field`: its classes, its
		style, its attributes and calls to `set`. A stylesheet never writes
		these, as an element's own styles win over its stylesheet's in
		Tailwind's layers. Null until one is set.
	**/
	var own:Null<Map<Int, Bool>> = null;

	/** Properties a stylesheet set, by `field`, so one no rule sets any more can be unset. **/
	var styled:Null<Map<Int, Bool>> = null;

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
			case 53 | 54 | 55 | 56 | 57 | 58: raw - 43;
			case 59: 26;
			case 66: 9;
			case _: raw;
		}
	}

	/** The shorthand a field is part of, which owning covers it: `Padding` for `PaddingTop`. **/
	static function shorthand(key:Int):Int {
		return switch key {
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
			styled = new Map();
		var fresh = !styled.exists(key);
		styled.set(key, true);
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
	var batch:Null<Map<Int, Void->Void>> = null;

	/** Runs `writes`, the stylesheet's writes to this node, then makes the last write to each field. **/
	@:allow(ashui.css)
	function styleAll(writes:Void->Void):Void {
		var outer = batch;
		batch = new Map();
		try
			writes()
		catch (e:haxe.Exception) {
			batch = outer;
			throw e;
		}
		var held = batch;
		batch = outer;
		for (write in held)
			write();
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
		// Under a transition that covers it, it moves back to its initial value rather than jumping there.
		var prop:PropertyId = key;
		var tween = tweens == null ? null : tweens.get(prop);
		var initial = ashui.animation.Tweened.initial(prop);
		if (tween != null && initial != null && transition != null && transition.covers(prop)) {
			tween.follow(Const(initial));
			return;
		}
		// Forgotten, so a later value starts a tween from where the property is, not from where this one left it.
		if (tween != null)
			tweens.remove(prop);
		BlincNative.blinc_unset(id, key);
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
			case TypeBrush | TypeColor | TypeCornerRadius | TypeTransform | TypeShadow | TypeClipPath:
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
	}

	/** Binds an `Int` property, enums included. **/
	public function applyI32(prop:PropertyId, reactive:IntoReactive<Int>):Void {
		switch (reactive) {
			case Const(v):
				BlincNative.blinc_apply_i32(id, prop, KIND_CONST, v, null, null);
			case Bound(s):
				BlincNative.blinc_apply_i32(id, prop, KIND_SIGNAL, 0, s.ptr, null);
			case Derived(c):
				BlincNative.blinc_apply_i32(id, prop, KIND_COMPUTED, 0, null, c.ptr);
		}
		Guard.check();
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
	}
}
