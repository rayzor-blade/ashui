package ashui.reactive;

import ashui.core.externs.BlincNative;

/** As `SignalDynamic`: the value stays in Haxe, Blinc tracks a version number. **/
class ComputedDynamic<T> implements IComputed<T> {
	public var ptr(default, null):hl.Abstract<"blinc_computed">;

	var last:T;
	var version = 0;

	public function new(compute:Void->T) {
		ptr = BlincNative.blinc_computed_i32(Guard.wrap(() -> {
			last = compute();
			BlincNative.blinc_return_i32(++version);
		}));
	}

	public function get():T {
		BlincNative.blinc_computed_touch(ptr);
		Guard.check();
		return last;
	}
}
