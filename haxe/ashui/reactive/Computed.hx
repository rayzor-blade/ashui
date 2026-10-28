package ashui.reactive;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
#end

/**
	Derives a reactive value from signals or other computeds:

	```haxe
	var doubled = computed(() -> count.get() * 2);
	```

	Import `ashui.reactive.Reactive` for `computed`, or use `Computed.make`.
	The function tracks the values it reads. When those dependencies change,
	the computed updates and notifies its own dependents. A computed can also
	bind directly to a node property. See `IntoReactive`.

	Keep the function read-only. Use a `Watch` for side effects; do not set
	signals or create watches inside a computed. The current `Owner` releases
	the computed when disposed. This is similar to SolidJS's `createMemo`.
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
