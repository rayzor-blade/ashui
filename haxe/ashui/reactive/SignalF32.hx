package ashui.reactive;

import ashui.core.externs.Handles;
import ashui.core.externs.BlincNative;

/** A signal of a `Single`; what `Signal.make` makes for one. **/
class SignalF32 implements ISignal<Single> {
	public var ptr(default, null):SignalHandle;

	var released = false;
	var frozen:Single = 0;

	public function new(initialValue:Single) {
		ptr = BlincNative.blinc_signal_f32(initialValue);
	}

	/**
		Frees the native signal, for good: it then keeps the value it had and ignores writes. Safe to call twice.
		Rayzor has no collector to do this; on HashLink it is optional.
	**/
	public function dispose():Void {
		if (released)
			return;
		frozen = BlincNative.blinc_signal_get_f32(ptr);
		released = true;
		BlincNative.blinc_signal_release(ptr);
		ptr = null;
	}

	public function get():Single {
		return released ? frozen : BlincNative.blinc_signal_get_f32(ptr);
	}

	public function set(val:Single):Void {
		if (released)
			return;
		BlincNative.blinc_signal_set_f32(ptr, val);
		Guard.check();
		ashui.core.Work.notify();
	}
}
