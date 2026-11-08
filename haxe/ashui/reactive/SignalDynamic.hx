package ashui.reactive;

import ashui.core.externs.Handles;
import ashui.core.externs.BlincNative;

/**
	A signal of any Haxe value without a native kind: an array, a structure,
	an object. The value stays on the Haxe heap; natively there is only a
	version number, which changes on every `set`, and that is what readers
	depend on. So every `set` notifies them, even of an equal value, and a
	change made inside the value notifies no one.
**/
class SignalDynamic<T> implements ISignal<T> {
	public var ptr(default, null):SignalHandle;

	var current:T;
	var version = 0;
	var released = false;

	public function new(initialValue:T) {
		current = initialValue;
		ptr = BlincNative.blinc_signal_i32(version);
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
		BlincNative.blinc_signal_set_i32(ptr, ++version);
		Guard.check();
		ashui.core.Work.notify();
	}
}
