package ashui.reactive;

import ashui.core.externs.BlincNative;
import ashui.types.IValue;

/**
	A signal of a style value. Blinc holds the native value for bindings; the
	wrapper object last set is kept here and returned by `get`.
**/
class SignalValue<T:IValue> implements ISignal<T> {
	public var ptr(default, null):hl.Abstract<"blinc_signal">;

	var current:T;

	public function new(initialValue:T) {
		current = initialValue;
		Guard.creating("A signal");
		ptr = BlincNative.blinc_signal_value(initialValue == null ? null : initialValue.ptr);
	}

	public function get():T {
		BlincNative.blinc_signal_touch(ptr);
		return current;
	}

	public function set(val:T):Void {
		current = val;
		BlincNative.blinc_signal_set_value(ptr, val == null ? null : val.ptr);
		Guard.check();
	}
}
