package ashui.reactive;

import ashui.core.externs.BlincNative;

class SignalF64 implements ISignal<Float> {
	public var ptr(default, null):hl.Abstract<"blinc_signal">;

	public function new(initialValue:Float) {
		Guard.creating("A signal");
		ptr = BlincNative.blinc_signal_f64(initialValue);
	}

	public function get():Float {
		return BlincNative.blinc_signal_get_f64(ptr);
	}

	public function set(val:Float):Void {
		BlincNative.blinc_signal_set_f64(ptr, val);
		Guard.check();
	}
}
