package ashui.reactive;

import ashui.core.Utf8;
import ashui.core.externs.BlincNative;

/** Held natively as UTF-8. Null reads back as "". **/
class ComputedString implements IComputed<String> {
	public var ptr(default, null):hl.Abstract<"blinc_computed">;

	public function new(compute:Void->String) {
		ptr = BlincNative.blinc_computed_string(Guard.wrap(() -> BlincNative.blinc_return_string(Utf8.encode(compute()))));
		Owner.adoptComputed(ptr);
	}

	public function get():String {
		var v = Utf8.decode(BlincNative.blinc_computed_get_string(ptr));
		Guard.check();
		return v;
	}
}
