package ashui.reactive;

import ashui.core.externs.BlincNative;

class ComputedF32 implements IComputed<Single> {
	public var ptr(default, null):hl.Abstract<"blinc_computed">;

	public function new(compute:Void->Single) {
		ptr = BlincNative.blinc_computed_f32(Guard.wrap(() -> BlincNative.blinc_return_f32(compute())));
		Owner.adoptComputed(ptr);
	}

	public function get():Single {
		var v = BlincNative.blinc_computed_get_f32(ptr);
		Guard.check();
		return v;
	}
}
