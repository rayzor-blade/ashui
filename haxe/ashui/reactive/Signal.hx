package ashui.reactive;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
#end

/**
	A value that changes, and that what reads it follows: make one with
	`Signal.make(initial)`, read it with `get()` and change it with `set(v)`.

	Reading a signal inside a `Computed`, a `Watch`'s `read`, or a template
	attribute records it as a dependency, so that runs again when the signal
	is set; read anywhere else, it is a plain read. Given to a node property
	(see `IntoReactive`), the property follows it. A signal is not owned:
	disposing an `Owner` does not release it.

	`make` picks the class for the value's type. `Int`, `Single`, `Float`,
	`Bool`, `String` and style values (`ashui.types.IValue`) are held
	natively, where property bindings read them; any other value stays in
	Haxe (see `SignalDynamic`). The dependency graph is Blinc's.
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
