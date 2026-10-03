package ashui.reactive;

import ashui.core.externs.BlincNative;
import ashui.types.IValue;

/**
	A computed style value, as `SignalValue` is a signal of one: the native
	value is held for property bindings, and the Haxe object last computed
	is returned by `get`.
**/
class ComputedValue<T:IValue> implements IComputed<T> {
	public var ptr(default, null):hl.Abstract<"blinc_computed">;

	var last:T;

	public function new(compute:Void->T) {
		ptr = BlincNative.blinc_computed_value(Guard.wrap(() -> {
			last = compute();
			BlincNative.blinc_return_value(last == null ? null : last.ptr);
		}));
		Owner.adoptComputed(ptr);
	}

	public function get():T {
		BlincNative.blinc_computed_touch(ptr);
		Guard.check();
		return last;
	}
}
