package ashui.reactive;

import ashui.core.externs.Handles;
import ashui.core.externs.BlincNative;

/** A signal of an `Int`, or an enum abstract over one; what `Signal.make` makes for those. **/
class SignalI32 implements ISignal<Int> {
	public var ptr(default, null):SignalHandle;

	var released = false;
	var frozen:Int = 0;

	public function new(initialValue:Int) {
		ptr = BlincNative.blinc_signal_i32(initialValue);
	}

	/**
		Frees the native signal, for good: it then keeps the value it had and ignores writes. Safe to call twice.
		Rayzor has no collector to do this; on HashLink it is optional.
	**/
	public function dispose():Void {
		if (released)
			return;
		frozen = BlincNative.blinc_signal_get_i32(ptr);
		released = true;
		BlincNative.blinc_signal_release(ptr);
		ptr = null;
	}

	public function get():Int {
		return released ? frozen : BlincNative.blinc_signal_get_i32(ptr);
	}

	public function set(val:Int):Void {
		if (released)
			return;
		BlincNative.blinc_signal_set_i32(ptr, val);
		Guard.check();
		ashui.core.Work.notify();
	}
}
