package ashui.reactive;

#if ashui_rayzor
import ashui.core.externs.Handles;
import ashui.core.externs.BlincNative;

/** A computed `Float`, run by the host; see `ComputedSlot`. **/
class ComputedF64 implements IComputed<Float> {
	public var ptr(default, null):ComputedHandle;

	final host:ComputedSlot;
	final compute:Void->Float;
	var next:Float = 0;
	var last:Float = 0;

	public function new(compute:Void->Float) {
		this.compute = ashui.core.UiContext.capture(compute);
		host = new ComputedSlot(evaluate, commit);
		host.first();
		Owner.onCleanup(dispose);
	}

	function evaluate():Void
		next = compute();

	function commit():Void {
		if (ptr == null) {
			ptr = BlincNative.blinc_signal_f64(next);
			last = next;
		} else if (next != last) {
			last = next;
			BlincNative.blinc_signal_set_f64(ptr, next);
			host.wrote();
		}
	}

	public function get():Float {
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

/** A computed `Float`; what `Computed.make` makes for one. **/
class ComputedF64 implements IComputed<Float> {
	public var ptr(default, null):ComputedHandle;

	public function new(compute:Void->Float) {
		compute = ashui.core.UiContext.capture(compute);
		ptr = BlincNative.blinc_computed_f64(Guard.wrap(() -> BlincNative.blinc_return_f64(compute())));
		Owner.adoptComputed(ptr);
	}

	public function get():Float {
		var v = BlincNative.blinc_computed_get_f64(ptr);
		Guard.check();
		return v;
	}
}
#end
