package ashui.layout;

import ashui.reactive.State;
import ashui.reactive.Computed;

/**
 * Mirrors blinc_layout::binding::Reactive<T>
 */
enum ReactiveType<T> {
    Const(value: T);
    Bound(state: State<T>);
    Computed(computed: Computed<T>);
}

/**
 * Mirrors blinc_layout::binding::IntoReactive<T> 
 * Provides zero-cost conversion at compile time for Coconut attributes.
 */
@:forward
abstract IntoReactive<T>(ReactiveType<T>) from ReactiveType<T> to ReactiveType<T> {
    
    @:from 
    public static inline function fromConst<T>(val: T): IntoReactive<T> {
        return Const(val);
    }
    
    @:from 
    public static inline function fromState<T>(state: State<T>): IntoReactive<T> {
        return Bound(state);
    }
    
    @:from 
    public static inline function fromComputed<T>(comp: Computed<T>): IntoReactive<T> {
        return Computed(comp);
    }
}