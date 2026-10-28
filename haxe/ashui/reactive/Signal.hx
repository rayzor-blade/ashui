package ashui.reactive;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
#end

/**
	Stores a reactive value. Create one with `signal(initial)` from
	`ashui.reactive.Reactive`, read it with `get()` and update it with `set(v)`.
	`Signal.make(initial)` is the equivalent macro API.

	Reads inside a computed, a watch's `read` function or a reactive template
	attribute register a dependency. Changes invalidate those dependents.
	Reads elsewhere return the value without subscribing. Passing a signal
	to a node property binds that property to it. See `IntoReactive`.

	The macro selects storage from the value's type. Integers, floats,
	booleans, strings and `ashui.types.IValue` style values use native storage.
	Other values stay in Haxe through `SignalDynamic`. Blinc manages the
	dependency graph. Signals are not owned by `Owner` and survive its disposal.
**/
// The macros below load this module in the macro context too, where `hl`
// types do not exist, so there it is a plain stand-in.
#if !macro
@:forward(get, set, ptr)
abstract Signal<T>(ISignal<T>) from ISignal<T> to ISignal<T> {
#else
abstract Signal<T>(Dynamic) {
#end

/** A signal of the native kind matching the type of `initialValue`. **/
macro public static function make(initialValue:Expr):Expr {
	return Kinds.build("Signal", Context.typeof(initialValue), initialValue);
}

/** A computed of `fn` applied to this signal's value. **/
public macro function computed(self:Expr, fn:Expr):Expr {
	return macro {
		var __signal = $self;
		ashui.reactive.Computed.make(() -> ashui.reactive.Signal.apply(__signal.get(), $fn));
	};
}

/** Types `v` before `f`, so a lambda's parameter takes the signal's type. **/
@:noCompletion public static inline function apply<A, R>(v:A, f:A->R):R {
	return f(v);
}
}
