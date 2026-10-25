package ashui.reactive;

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
