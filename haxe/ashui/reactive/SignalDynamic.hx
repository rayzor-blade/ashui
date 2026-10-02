package ashui.reactive;

import ashui.core.externs.BlincNative;

/**
	A signal of any Haxe value. The value stays on the Haxe heap, out of reach
	of Rust; Blinc holds a version number that changes on every `set`, and
	that is what readers depend on.
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
