package ashui.layout;

import ashui.reactive.Signal;
import ashui.reactive.Computed;

/**
 * Mirrors blinc_layout::binding::Reactive<T>
 */
enum ReactiveType<T> {
    Const(value: T);
    Bound(state: Signal<T>);
    /** A computed's value; named apart from `Computed`, which this enum would otherwise shadow wherever it is imported. **/
    Derived(computed: Computed<T>);
}

/**
 * Mirrors blinc_layout::binding::IntoReactive<T> 
 * Provides zero-cost conversion at compile time for UI attributes.
 */
@:forward
abstract IntoReactive<T>(ReactiveType<T>) from ReactiveType<T> to ReactiveType<T> {
    
    @:from 
    public static inline function fromConst<T>(val: T): IntoReactive<T> {
        return Const(val);
    }
    
    /** Number literals for `Single` properties, which would otherwise need two implicit casts. **/
    @:from
    public static inline function fromInt(val: Int): IntoReactive<Single> {
        return Const((val : Single));
    }

    @:from
    public static inline function fromFloat(val: Float): IntoReactive<Single> {
        return Const((val : Single));
    }

    @:from
    public static inline function fromState<T>(state: Signal<T>): IntoReactive<T> {
        return Bound(state);
    }
    
    @:from 
    public static inline function fromComputed<T>(comp: Computed<T>): IntoReactive<T> {
        return Derived(comp);
    }
}