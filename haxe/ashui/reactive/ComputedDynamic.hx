package ashui.reactive;

#if ashui_rayzor
import ashui.core.externs.Handles;
import ashui.core.externs.BlincNative;

/**
	A computed of any Haxe value without a native kind, run by the host; see `ComputedSlot`. The value
	stays in Haxe and natively only a version number changes, on every run, equal value or not.
**/
class ComputedDynamic<T> implements IComputed<T> {
	public var ptr(default, null):ComputedHandle;

	final host:ComputedSlot;
	final compute:Void->T;
	var last:T;
	var version = 0;

	public function new(compute:Void->T) {
		this.compute = ashui.core.UiContext.capture(compute);
		host = new ComputedSlot(evaluate, commit);
		host.first();
		Owner.onCleanup(dispose);
	}

	function evaluate():Void
		last = compute();

	function commit():Void {
		if (ptr == null) {
			ptr = BlincNative.blinc_signal_i32(version);
		} else {
			BlincNative.blinc_signal_set_i32(ptr, ++version);
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

/**
	A computed of any Haxe value without a native kind, as `SignalDynamic`
	is a signal of one: the value stays in Haxe, and natively only a version
	number changes, each time the closure runs again.
**/
class ComputedDynamic<T> implements IComputed<T> {
	public var ptr(default, null):ComputedHandle;

	var last:T;
	var version = 0;

	public function new(compute:Void->T) {
		compute = ashui.core.UiContext.capture(compute);
		ptr = BlincNative.blinc_computed_i32(Guard.wrap(() -> {
			last = compute();
			BlincNative.blinc_return_i32(++version);
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
