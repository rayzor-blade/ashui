package ashui.reactive;

import ashui.core.externs.Handles;
import ashui.core.Utf8;
import ashui.core.externs.BlincNative;

/**
	A computed `String`, held natively as UTF-8 so property bindings can read it. The Haxe string the closure last made is
	kept too, so a read brings the computed up to date and returns that, decoding nothing.
**/
class ComputedString implements IComputed<String> {
	public var ptr(default, null):ComputedHandle;

	var cached:Null<String> = null;

	public function new(compute:Void->String) {
		compute = ashui.core.UiContext.capture(compute);
		ptr = BlincNative.blinc_computed_string(Guard.wrap(() -> {
			var made = compute();
			cached = made;
			return BlincNative.blinc_return_string(Utf8.encode(made));
		}));
		Owner.adoptComputed(ptr);
	}

	public function get():String {
		BlincNative.blinc_computed_touch(ptr);
		Guard.check();
		return cached;
	}
}
