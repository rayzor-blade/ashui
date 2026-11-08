package ashui.reactive;

#if ashui_rayzor
import ashui.core.externs.Handles;
import ashui.core.externs.BlincNative;

/** A computed `Single`, run by the host; see `ComputedSlot`. **/
class ComputedF32 implements IComputed<Single> {
	public var ptr(default, null):ComputedHandle;

	final host:ComputedSlot;
	final compute:Void->Single;
	var next:Single = 0;
	var last:Single = 0;

	public function new(compute:Void->Single) {
		this.compute = ashui.core.UiContext.capture(compute);
		host = new ComputedSlot(evaluate, commit);
		host.first();
		Owner.onCleanup(dispose);
	}

	function evaluate():Void
		next = compute();

	function commit():Void {
		if (ptr == null) {
			ptr = BlincNative.blinc_signal_f32(next);
			last = next;
		} else if (next != last) {
			last = next;
			BlincNative.blinc_signal_set_f32(ptr, next);
			host.wrote();
		}
	}

	public function get():Single {
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

/** A computed `Single`; what `Computed.make` makes for one. **/
class ComputedF32 implements IComputed<Single> {
	public var ptr(default, null):ComputedHandle;

	public function new(compute:Void->Single) {
		compute = ashui.core.UiContext.capture(compute);
		ptr = BlincNative.blinc_computed_f32(Guard.wrap(() -> BlincNative.blinc_return_f32(compute())));
		Owner.adoptComputed(ptr);
	}

	public function get():Single {
		var v = BlincNative.blinc_computed_get_f32(ptr);
		Guard.check();
		return v;
	}
}
#end
