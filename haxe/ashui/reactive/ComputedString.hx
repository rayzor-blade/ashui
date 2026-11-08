package ashui.reactive;

#if ashui_rayzor
import ashui.core.externs.Handles;
import ashui.core.externs.BlincNative;

/** A computed `String`, run by the host; see `ComputedSlot`. The native copy is UTF-8, for property bindings. **/
class ComputedString implements IComputed<String> {
	public var ptr(default, null):ComputedHandle;

	final host:ComputedSlot;
	final compute:Void->String;
	var next:String = "";
	var last:String = "";

	public function new(compute:Void->String) {
		this.compute = ashui.core.UiContext.capture(compute);
		host = new ComputedSlot(evaluate, commit);
		host.first();
		Owner.onCleanup(dispose);
	}

	function evaluate():Void
		next = compute();

	function commit():Void {
		if (ptr == null) {
			ptr = BlincNative.blinc_signal_string(ashui.core.Utf8.toNative(next));
			last = next;
		} else if (next != last) {
			last = next;
			BlincNative.blinc_signal_set_string(ptr, ashui.core.Utf8.toNative(next));
			host.wrote();
		}
	}

	public function get():String {
		host.read(ptr);
		return last;
	}

	/** Stops the computed and frees its native signal, for good: it then keeps the value it had. Its owner does this; twice is harmless. **/
	public function dispose():Void {
		host.free(ptr);
		ptr = null;
	}
}
#else
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
			return BlincNative.blinc_return_string(Utf8.toNative(made));
		}));
		Owner.adoptComputed(ptr);
	}

	public function get():String {
		BlincNative.blinc_computed_touch(ptr);
		Guard.check();
		return cached;
	}
}
#end
