package ashui.layout;

import ashui.core.Utf8;
import ashui.core.externs.BlincNative;
import ashui.layout.IntoReactive;
import ashui.layout.PropertyId;
import ashui.reactive.Guard;
import ashui.types.IValue;

class Node {
	// How a router reads its arguments: the constant, the signal or the computed.
	static inline var KIND_CONST = 0;
	static inline var KIND_SIGNAL = 1;
	static inline var KIND_COMPUTED = 2;

	// 64-bit LayoutNodeId minted by Blinc
	public var id(default, null):haxe.Int64;

	/** The tree that made this node. **/
	public var tree(default, null):Null<LayoutTree>;

	/** What animates when a property it covers is set again or its value changes. **/
	public var transition(default, set):Null<ashui.animation.Transition>;

	var tweens:Null<Map<Int, ashui.animation.Tweened<Dynamic>>>;

	function set_transition(value:Null<ashui.animation.Transition>) {
		return transition = value;
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
		var key:PropertyId = prop;
		if (transition != null && transition.covers(key) && !isCornerShape(reactive)) {
			if (tweens == null)
				tweens = new Map();
			var tween = tweens.get(key);
			if (tween != null) {
				tween.follow(cast reactive);
				return;
			}
			tween = ashui.animation.Tweened.bind(this, key, transition, cast reactive);
			if (tween != null) {
				tweens.set(key, tween);
				return;
			}
		}
		bind(prop, reactive);
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

	/** Brushes, colors, radii, transforms and shadows. **/
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
