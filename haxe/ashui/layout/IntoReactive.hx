package ashui.layout;

import ashui.reactive.Signal;
import ashui.reactive.Computed;

/**
	The three things a property can be given: a constant (`Const`), a
	signal (`Bound`) or a computed (`Derived`). Code meets it as
	`IntoReactive<T>`, which converts to it implicitly; switch on it to treat
	the three apart. Mirrors Blinc's `Reactive<T>`.
**/
enum ReactiveType<T> {
    /** A value, applied once. **/
    Const(value: T);
    /** A signal, followed as it is set. **/
    Bound(state: Signal<T>);
    /** A computed's value; named apart from `Computed`, which this enum would otherwise shadow wherever it is imported. **/
    Derived(computed: Computed<T>);
}

/**
	What a property accepts: a constant, a `Signal<T>` or a `Computed<T>`,
	each converted implicitly. So `node.set(Prop.Width, 120)`,
	`node.set(Prop.Width, width)` with `width` a signal, and
	`node.set(Prop.Width, Computed.make(() -> width.get() * 2))` all type,
	and so do the same values given to a `Div` attribute or to a component
	prop typed `IntoReactive<T>`.

	A constant is applied once. A signal or computed is bound: applied now
	and again on every change, with no watch or callback to write. The
	property follows each `set` of a signal, and each new value of a
	computed as what it read changes; each takes effect at the next
	`LayoutTree.flush`. The conversion is resolved at compile time and
	inlined. Mirrors Blinc's `IntoReactive<T>`.
**/
@:forward
abstract IntoReactive<T>(ReactiveType<T>) from ReactiveType<T> to ReactiveType<T> {
    
    /** A constant, applied once. **/
    @:from 
    public static inline function fromConst<T>(val: T): IntoReactive<T> {
        return Const(val);
    }
    
    /** Number literals for `Single` properties, which would otherwise need two implicit casts. **/
    @:from
    public static inline function fromInt(val: Int): IntoReactive<Single> {
        return Const((val : Single));
    }

    /** As `fromInt`, for a `Float`. **/
    @:from
    public static inline function fromFloat(val: Float): IntoReactive<Single> {
        return Const((val : Single));
    }

    /** A signal: the property follows each `set`. **/
    @:from
    public static inline function fromState<T>(state: Signal<T>): IntoReactive<T> {
        return Bound(state);
    }
    
    /**
        A Float signal or computed on a `Single` property. The binding stays
        on it and narrows on read, so it follows every change.
    **/
    @:from
    public static inline function fromFloatSignal(state: Signal<Float>): IntoReactive<Single> {
        return Bound(cast state);
    }

    @:from
    public static inline function fromFloatComputed(comp: Computed<Float>): IntoReactive<Single> {
        return Derived(cast comp);
    }

    /** A computed: the property follows each new value. **/
    @:from 
    public static inline function fromComputed<T>(comp: Computed<T>): IntoReactive<T> {
        return Derived(comp);
    }
}