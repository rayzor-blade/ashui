package ashui.reactive;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
#end

/**
	A value derived from signals and other computeds:
	`Computed.make(() -> count.get() * 2)`. Its closure runs again when
	anything it read on its last run changes, so `get()` stays current, and
	what reads the computed follows it in turn. Like a signal, it can be
	given to a node property (see `IntoReactive`).

	The closure only reads: it must not set signals or make a `Watch`; to act
	on a change, use a `Watch`. A computed belongs to the `Owner` current
	when it is made, and is released when that owner is disposed. Modelled
	on SolidJS's `createMemo`.
**/
// The macros below load this module in the macro context too, where `hl`
// types do not exist, so there it is a plain stand-in.
#if !macro
@:forward(get, ptr)
abstract Computed<T>(IComputed<T>) from IComputed<T> to IComputed<T> {
#else
abstract Computed<T>(Dynamic) {
#end
	/** A computed of the native kind matching what `compute` returns. **/
	macro public static function make(compute:Expr):Expr {
		return Kinds.build("Computed", Context.typeof(macro $compute()), compute);
	}
}
