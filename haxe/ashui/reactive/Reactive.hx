/**
	Short spellings for making reactive values, as SolidJS reads them:

	```haxe
	import ashui.reactive.Reactive;   // brings signal, computed and watch in

	var count = signal(0);
	var doubled = computed(() -> count.get() * 2);
	watch(() -> doubled.get(), v -> trace(v));
	```

	`signal` and `computed` are `Signal.make` and `Computed.make`: the value's
	type still picks the kind of signal, at compile time.
**/
package ashui.reactive;

#if macro
import haxe.macro.Expr;
#end

/** A signal holding `value`, typed by it: `Signal.make(value)`. **/
macro function signal(value:Expr):Expr
	return macro @:pos(value.pos) ashui.reactive.Signal.make($value);

/** A computed of `fn`, run again when what it read changes: `Computed.make(fn)`. **/
macro function computed(fn:Expr):Expr
	return macro @:pos(fn.pos) ashui.reactive.Computed.make($fn);

#if !macro
/** Calls `react` with what `read` returns each time that changes: `new Watch(read, react)`. **/
function watch<T>(read:Void->T, react:T->Void):Watch<T>
	return new Watch(read, react);
#end
