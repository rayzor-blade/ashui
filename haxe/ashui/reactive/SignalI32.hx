package ashui.reactive;

import ashui.core.externs.BlincNative;

class SignalI32 implements ISignal<Int> {
	public var ptr(default, null):hl.Abstract<"blinc_signal">;

	public function new(initialValue:Int) {
		Guard.creating("A signal");
		ptr = BlincNative.blinc_signal_i32(initialValue);
	}

	public function get():Int {
		return BlincNative.blinc_signal_get_i32(ptr);
	}

	public function set(val:Int):Void {
		BlincNative.blinc_signal_set_i32(ptr, val);
		Guard.check();
	}
}
