package ashui.reactive;

import ashui.core.Utf8;
import ashui.core.externs.BlincNative;

/** Held natively as UTF-8 so property bindings can read it. **/
class SignalString implements ISignal<String> {
	public var ptr(default, null):hl.Abstract<"blinc_signal">;

	public function new(initialValue:String) {
		Guard.creating("A signal");
		ptr = BlincNative.blinc_signal_string(Utf8.encode(initialValue));
	}

	public function get():String {
		return Utf8.decode(BlincNative.blinc_signal_get_string(ptr));
	}

	public function set(val:String):Void {
		BlincNative.blinc_signal_set_string(ptr, Utf8.encode(val));
		Guard.check();
	}
}
