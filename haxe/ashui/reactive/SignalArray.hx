package ashui.reactive;

/**
	A signal of an array, which changes when `set` replaces it. Mutating the
	array in place is not seen by readers. What `Signal.make` makes for an
	array, and what a `For` usually iterates.
**/
class SignalArray<T> extends SignalDynamic<Array<T>> {}
