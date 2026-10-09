package ashui.reactive;

import ashui.core.externs.BlincNative;
import ashui.types.IValue;

/**
	A signal of a style value (`ashui.types.IValue`): a `Brush`, `Color`,
	`CornerRadius`, `Transform`, `Shadow` and the like. The native value is
	held for property bindings to read; the Haxe object last set is kept
	here and returned by `get`.
**/
class SignalValue<T:IValue> implements ISignal<T> {
	public var ptr(default, null):hl.Abstract<"blinc_signal">;

	var current:T;

	public function new(initialValue:T) {
		current = initialValue;
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
		ashui.core.Work.notify();
	}
}
