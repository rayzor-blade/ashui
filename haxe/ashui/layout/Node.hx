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
		return transition = value;
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

	/** `set` without claiming the property: how transitions and stylesheets write. **/
	function apply<T>(prop:Prop<T>, reactive:IntoReactive<T>):Void {
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
			tween = ashui.animation.Tweened.bind(this, key, timing, cast reactive);
			if (tween != null) {
				tweens.set(key, tween);
				return;
			}
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
		styled.set(key, true);
		// An animation's frames are each where the property is, not somewhere to move to.
		if (immediate) {
			var id:PropertyId = prop;
			var tween = tweens == null ? null : tweens.get(id);
			if (tween != null)
				@:privateAccess tween.jump(value);
			else
				bind(prop, Const(value));
		} else
			apply(prop, Const(value));
		return true;
	}

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
		if (!owns(key))
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
