package ashui.reactive;

import ashui.core.externs.Handles;
import ashui.core.Utf8;
import ashui.core.externs.BlincNative;

/**
	A signal of a `String`, held natively as UTF-8 so property bindings can
	read it. `get()` caches the decoded Haxe string by the native version,
	so repeated reads between writes decode nothing.
**/
class SignalString implements ISignal<String> {
	public var ptr(default, null):SignalHandle;

	var cached:String;
	var cachedVersion:Int;
	var released = false;

	public function new(initialValue:String) {
		ptr = BlincNative.blinc_signal_string(Utf8.encode(initialValue));
		cached = initialValue;
		cachedVersion = BlincNative.blinc_signal_string_version(ptr);
	}

	/**
		Frees the native signal, for good: it then keeps the value it had and ignores writes. Safe to call twice.
		Rayzor has no collector to do this; on HashLink it is optional.
	**/
	public function dispose():Void {
		if (released)
			return;
		// Keep what a read would find, without tracking the read.
		var version = BlincNative.blinc_signal_string_version(ptr);
		if (version != cachedVersion) {
			cached = Utf8.decode(BlincNative.blinc_signal_get_string(ptr));
			cachedVersion = version;
		}
		released = true;
		BlincNative.blinc_signal_release(ptr);
		ptr = null;
	}

	public function get():String {
		if (released)
			return cached;
		BlincNative.blinc_signal_touch(ptr);
		var version = BlincNative.blinc_signal_string_version(ptr);
		if (version != cachedVersion) {
			cached = Utf8.decode(BlincNative.blinc_signal_get_string(ptr));
			cachedVersion = version;
		}
		return cached;
	}

	public function set(val:String):Void {
		if (released)
			return;
		BlincNative.blinc_signal_set_string(ptr, Utf8.encode(val));
		// What was written is what a read finds, so the next read decodes nothing.
		cached = val;
		cachedVersion = BlincNative.blinc_signal_string_version(ptr);
		Guard.check();
		ashui.core.Work.notify();
	}
}
