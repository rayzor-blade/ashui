package ashui.reactive;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
#end

/**
	A value derived from signals. Its closure re-runs when any signal it read
	on its last run changes, like SolidJS's `createMemo`. The closure must not
	set signals.
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
