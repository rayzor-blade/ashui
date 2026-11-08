package ashui.reactive;

#if ashui_rayzor
import ashui.core.externs.Handles;
import ashui.core.externs.BlincNative;

/** A computed `Int`, or an enum abstract over one, run by the host; see `ComputedSlot`. **/
class ComputedI32 implements IComputed<Int> {
	public var ptr(default, null):ComputedHandle;

	final host:ComputedSlot;
	final compute:Void->Int;
	var next:Int = 0;
	var last:Int = 0;

	public function new(compute:Void->Int) {
		this.compute = ashui.core.UiContext.capture(compute);
		host = new ComputedSlot(evaluate, commit);
		host.first();
		Owner.onCleanup(dispose);
	}

	function evaluate():Void
		next = compute();

	function commit():Void {
		if (ptr == null) {
			ptr = BlincNative.blinc_signal_i32(next);
			last = next;
		} else if (next != last) {
			last = next;
			BlincNative.blinc_signal_set_i32(ptr, next);
			host.wrote();
		}
	}

	public function get():Int {
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

/** A computed `Int`, or an enum abstract over one; what `Computed.make` makes for those. **/
class ComputedI32 implements IComputed<Int> {
	public var ptr(default, null):ComputedHandle;

	public function new(compute:Void->Int) {
		compute = ashui.core.UiContext.capture(compute);
		ptr = BlincNative.blinc_computed_i32(Guard.wrap(() -> BlincNative.blinc_return_i32(compute())));
		Owner.adoptComputed(ptr);
	}

	public function get():Int {
		var v = BlincNative.blinc_computed_get_i32(ptr);
		Guard.check();
		return v;
	}
}
#end
