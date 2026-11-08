package ashui.reactive;

import ashui.core.externs.Handles;
import ashui.core.externs.BlincNative;
import ashui.types.IValue;

/**
	A signal of a style value (`ashui.types.IValue`): a `Brush`, `Color`,
	`CornerRadius`, `Transform`, `Shadow` and the like. The native value is
	held for property bindings to read; the Haxe object last set is kept
	here and returned by `get`.
**/
class SignalValue<T:IValue> implements ISignal<T> {
	public var ptr(default, null):SignalHandle;

	var current:T;
	var released = false;

	public function new(initialValue:T) {
		current = initialValue;
		ptr = BlincNative.blinc_signal_value(initialValue == null ? null : initialValue.ptr);
	}

	/**
		Frees the native signal, for good: it then keeps the value it had and ignores writes. Safe to call twice.
		Rayzor has no collector to do this; on HashLink it is optional.
	**/
	public function dispose():Void {
		if (released)
			return;
		released = true;
		BlincNative.blinc_signal_release(ptr);
		ptr = null;
	}

	public function get():T {
		if (!released)
			BlincNative.blinc_signal_touch(ptr);
		return current;
	}

	public function set(val:T):Void {
		if (released)
			return;
		current = val;
		BlincNative.blinc_signal_set_value(ptr, val == null ? null : val.ptr);
		Guard.check();
		ashui.core.Work.notify();
	}
}
