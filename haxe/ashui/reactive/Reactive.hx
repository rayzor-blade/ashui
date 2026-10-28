/**
	Convenience macros for reactive state:

	```haxe
	import ashui.reactive.Reactive;

	var count = signal(0);
	var doubled = computed(() -> count.get() * 2);
	watch(() -> doubled.get(), v -> trace(v));
	```

	`signal` and `computed` call `Signal.make` and `Computed.make`.
	The macros select the storage type at compile time.
**/

package ashui.reactive;

#if macro
import haxe.macro.Expr;
#end

/** Creates a signal initialized with `value`. Equivalent to `Signal.make(value)`. **/
macro function signal(value:Expr):Expr
	return macro @:pos(value.pos) ashui.reactive.Signal.make($value);

/** Creates a computed value that tracks the dependencies read by `fn`. Equivalent to `Computed.make(fn)`. **/
macro function computed(fn:Expr):Expr
	return macro @:pos(fn.pos) ashui.reactive.Computed.make($fn);

#if !macro
/** Runs `react` when the tracked result of `read` changes. Equivalent to `new Watch(read, react)`. **/
function watch<T>(read:Void->T, react:T->Void):Watch<T>
	return new Watch(read, react);
#end
