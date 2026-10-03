package ashui.reactive;

import ashui.core.externs.BlincNative;

class SignalF32 implements ISignal<Single> {
	public var ptr(default, null):hl.Abstract<"blinc_signal">;

	public function new(initialValue:Single) {
		ptr = BlincNative.blinc_signal_f32(initialValue);
	}

	public function get():Single {
		return BlincNative.blinc_signal_get_f32(ptr);
	}

	public function set(val:Single):Void {
		BlincNative.blinc_signal_set_f32(ptr, val);
		Guard.check();
	}
}
