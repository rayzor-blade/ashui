package ashui.reactive;

import ashui.core.externs.BlincNative;

/**
	A signal of any Haxe value without a native kind: an array, a structure,
	an object. The value stays on the Haxe heap; natively there is only a
	version number, which changes on every `set`, and that is what readers
	depend on. So every `set` notifies them, even of an equal value, and a
	change made inside the value notifies no one.
**/
class SignalDynamic<T> implements ISignal<T> {
	public var ptr(default, null):hl.Abstract<"blinc_signal">;

	var current:T;
	var version = 0;

	public function new(initialValue:T) {
		current = initialValue;
		ptr = BlincNative.blinc_signal_i32(version);
	}

	public function get():T {
		BlincNative.blinc_signal_touch(ptr);
		return current;
	}

	public function set(val:T):Void {
		current = val;
		BlincNative.blinc_signal_set_i32(ptr, ++version);
		Guard.check();
	}
}
