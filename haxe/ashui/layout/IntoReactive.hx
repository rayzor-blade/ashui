package ashui.layout;

import ashui.reactive.Signal;
import ashui.reactive.Computed;

/**
	Represents a constant (`Const`), signal (`Bound`) or computed (`Derived`).
	`IntoReactive<T>` converts these inputs implicitly. Switch on this enum to handle each case.
	Corresponds to Blinc's `Reactive<T>`.
**/
enum ReactiveType<T> {
	/** A value, applied once. **/
	Const(value:T);

	/** A signal, followed as it is set. **/
	Bound(state:Signal<T>);

	/** A computed's value; named apart from `Computed`, which this enum would otherwise shadow wherever it is imported. **/
	Derived(computed:Computed<T>);
}

/**
	Accepts a constant, `Signal<T>` or `Computed<T>` as a property value:

	```haxe
	node.set(Prop.Width, 120);
	node.set(Prop.Width, width);
	node.set(Prop.Width, computed(() -> width.get() * 2));
	```

	The same inputs work in element attributes and component props typed
	`IntoReactive<T>`. Import `ashui.reactive.Reactive` for `computed`.

	Constants are applied once. Signals and computeds create native bindings
	that update after changes, without an extra watch or callback.
	`LayoutTree.flush` applies the updates. Conversions are resolved and
	inlined at compile time. Corresponds to Blinc's `IntoReactive<T>`.
**/
@:forward
abstract IntoReactive<T>(ReactiveType<T>) from ReactiveType<T> to ReactiveType<T> {
	/** A constant, applied once. **/
	@:from
	public static inline function fromConst<T>(val:T):IntoReactive<T> {
		return Const(val);
	}

	/** Number literals for `Single` properties, which would otherwise need two implicit casts. **/
	@:from
	public static inline function fromInt(val:Int):IntoReactive<Single> {
		return Const((val : Single));
	}

	/** As `fromInt`, for a `Float`. **/
	@:from
	public static inline function fromFloat(val:Float):IntoReactive<Single> {
		return Const((val : Single));
	}

	/** A signal: the property follows each `set`. **/
	@:from
	public static inline function fromState<T>(state:Signal<T>):IntoReactive<T> {
		return Bound(state);
	}

	/**
		A Float signal or computed on a `Single` property. The binding stays
		on it and narrows on read, so it follows every change.
	**/
	@:from
	public static inline function fromFloatSignal(state:Signal<Float>):IntoReactive<Single> {
		return Bound(cast state);
	}

	@:from
	public static inline function fromFloatComputed(comp:Computed<Float>):IntoReactive<Single> {
		return Derived(cast comp);
	}

	/** A computed: the property follows each new value. **/
	@:from
	public static inline function fromComputed<T>(comp:Computed<T>):IntoReactive<T> {
		return Derived(comp);
	}
}
