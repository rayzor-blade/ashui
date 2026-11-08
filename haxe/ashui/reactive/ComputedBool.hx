package ashui.reactive;

#if ashui_rayzor
import ashui.core.externs.Handles;
import ashui.core.externs.BlincNative;

/** A computed `Bool`, run by the host; see `ComputedSlot`. **/
class ComputedBool implements IComputed<Bool> {
	public var ptr(default, null):ComputedHandle;

	final host:ComputedSlot;
	final compute:Void->Bool;
	var next:Bool = false;
	var last:Bool = false;

	public function new(compute:Void->Bool) {
		this.compute = ashui.core.UiContext.capture(compute);
		host = new ComputedSlot(evaluate, commit);
		host.first();
		Owner.onCleanup(dispose);
	}

	function evaluate():Void
		next = compute();

	function commit():Void {
		if (ptr == null) {
			ptr = BlincNative.blinc_signal_bool(next ? 1 : 0);
			last = next;
		} else if (next != last) {
			last = next;
			BlincNative.blinc_signal_set_bool(ptr, next ? 1 : 0);
			host.wrote();
		}
	}

	public function get():Bool {
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
import ashui.core.externs.BlincNative;

/** A computed `Bool`; what `Computed.make` makes for one. **/
class ComputedBool implements IComputed<Bool> {
	public var ptr(default, null):ComputedHandle;

	public function new(compute:Void->Bool) {
		compute = ashui.core.UiContext.capture(compute);
		ptr = BlincNative.blinc_computed_bool(Guard.wrap(() -> BlincNative.blinc_return_bool(compute() ? 1 : 0)));
		Owner.adoptComputed(ptr);
	}

	public function get():Bool {
		var v = BlincNative.blinc_computed_get_bool(ptr);
		Guard.check();
		return v;
	}
}
#end
