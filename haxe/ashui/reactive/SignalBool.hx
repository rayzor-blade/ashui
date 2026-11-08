package ashui.reactive;

import ashui.core.externs.Handles;
import ashui.core.externs.BlincNative;

/** A signal of a `Bool`; what `Signal.make` makes for one. **/
class SignalBool implements ISignal<Bool> {
	public var ptr(default, null):SignalHandle;

	var released = false;
	var frozen:Bool = false;

	public function new(initialValue:Bool) {
		ptr = BlincNative.blinc_signal_bool(initialValue ? 1 : 0);
	}

	/**
		Frees the native signal, for good: it then keeps the value it had and ignores writes. Safe to call twice.
		Rayzor has no collector to do this; on HashLink it is optional.
	**/
	public function dispose():Void {
		if (released)
			return;
		frozen = BlincNative.blinc_signal_get_bool(ptr);
		released = true;
		BlincNative.blinc_signal_release(ptr);
		ptr = null;
	}

	public function get():Bool {
		return released ? frozen : BlincNative.blinc_signal_get_bool(ptr);
	}

	public function set(val:Bool):Void {
		if (released)
			return;
		BlincNative.blinc_signal_set_bool(ptr, val ? 1 : 0);
		Guard.check();
		ashui.core.Work.notify();
	}
}
