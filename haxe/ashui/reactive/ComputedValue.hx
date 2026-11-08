package ashui.reactive;

#if ashui_rayzor
import ashui.types.IValue;
import ashui.core.externs.Handles;
import ashui.core.externs.BlincNative;

/**
	A computed style value, run by the host; see `ComputedSlot`. A function that makes a fresh value
	on each run leaves the previous one for its owner to free: it may be a constant shared elsewhere.
**/
class ComputedValue<T:IValue> implements IComputed<T> {
	public var ptr(default, null):ComputedHandle;

	final host:ComputedSlot;
	final compute:Void->T;
	var next:T;
	var last:T;

	public function new(compute:Void->T) {
		this.compute = ashui.core.UiContext.capture(compute);
		host = new ComputedSlot(evaluate, commit);
		host.first();
		Owner.onCleanup(dispose);
	}

	function evaluate():Void
		next = compute();

	function commit():Void {
		if (ptr == null) {
			ptr = BlincNative.blinc_signal_value(next == null ? null : next.ptr);
			last = next;
		} else if (next != last) {
			last = next;
			BlincNative.blinc_signal_set_value(ptr, next == null ? null : next.ptr);
			host.wrote();
		}
	}

	public function get():T {
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
import ashui.types.IValue;

/**
	A computed style value, as `SignalValue` is a signal of one: the native
	value is held for property bindings, and the Haxe object last computed
	is returned by `get`.
**/
class ComputedValue<T:IValue> implements IComputed<T> {
	public var ptr(default, null):ComputedHandle;

	var last:T;

	public function new(compute:Void->T) {
		compute = ashui.core.UiContext.capture(compute);
		ptr = BlincNative.blinc_computed_value(Guard.wrap(() -> {
			last = compute();
			BlincNative.blinc_return_value(last == null ? null : last.ptr);
		}));
		Owner.adoptComputed(ptr);
	}

	public function get():T {
		BlincNative.blinc_computed_touch(ptr);
		Guard.check();
		return last;
	}
}
#end
