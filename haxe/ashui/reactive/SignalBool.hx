package ashui.reactive;

import ashui.core.externs.BlincNative;

/** A signal of a `Bool`; what `Signal.make` makes for one. **/
class SignalBool implements ISignal<Bool> {
	public var ptr(default, null):hl.Abstract<"blinc_signal">;

	public function new(initialValue:Bool) {
		ptr = BlincNative.blinc_signal_bool(initialValue ? 1 : 0);
	}

	public function get():Bool {
		return BlincNative.blinc_signal_get_bool(ptr);
	}

	public function set(val:Bool):Void {
		BlincNative.blinc_signal_set_bool(ptr, val ? 1 : 0);
		Guard.check();
	}
}
