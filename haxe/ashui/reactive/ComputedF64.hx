package ashui.reactive;

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
