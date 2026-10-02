package ashui.reactive;

/**
	A signal of an array, which changes when `set` replaces it. Mutating the
	array in place is not seen by readers.
**/
class SignalArray<T> extends SignalDynamic<Array<T>> {}
