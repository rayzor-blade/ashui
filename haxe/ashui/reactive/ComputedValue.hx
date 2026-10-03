package ashui.reactive;

import ashui.core.externs.BlincNative;
import ashui.types.IValue;

/** As `SignalValue`: Blinc holds the native value, this the last wrapper computed. **/
class ComputedValue<T:IValue> implements IComputed<T> {
	public var ptr(default, null):hl.Abstract<"blinc_computed">;

	var last:T;

	public function new(compute:Void->T) {
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
