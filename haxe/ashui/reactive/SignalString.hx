package ashui.reactive;

import ashui.core.Utf8;
import ashui.core.externs.BlincNative;

/**
	A signal of a `String`, held natively as UTF-8 so property bindings can
	read it. `get()` caches the decoded Haxe string by the native version,
	so repeated reads between writes decode nothing.
**/
class SignalString implements ISignal<String> {
	public var ptr(default, null):hl.Abstract<"blinc_signal">;

	var cached:String;
	var cachedVersion:Int;

	public function new(initialValue:String) {
		ptr = BlincNative.blinc_signal_string(Utf8.encode(initialValue));
		cached = initialValue;
		cachedVersion = BlincNative.blinc_signal_string_version(ptr);
	}

	public function get():String {
		BlincNative.blinc_signal_touch(ptr);
		var version = BlincNative.blinc_signal_string_version(ptr);
		if (version != cachedVersion) {
			cached = Utf8.decode(BlincNative.blinc_signal_get_string(ptr));
			cachedVersion = version;
		}
		return cached;
	}

	public function set(val:String):Void {
		BlincNative.blinc_signal_set_string(ptr, Utf8.encode(val));
		// What was written is what a read finds, so the next read decodes nothing.
		cached = val;
		cachedVersion = BlincNative.blinc_signal_string_version(ptr);
		Guard.check();
		ashui.core.Work.notify();
	}
}
