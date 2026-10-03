package ashui.reactive;

import ashui.core.externs.BlincNative;

/**
	A computed of any Haxe value without a native kind, as `SignalDynamic`
	is a signal of one: the value stays in Haxe, and natively only a version
	number changes, each time the closure runs again.
**/
class ComputedDynamic<T> implements IComputed<T> {
	public var ptr(default, null):hl.Abstract<"blinc_computed">;

	var last:T;
	var version = 0;

	public function new(compute:Void->T) {
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
