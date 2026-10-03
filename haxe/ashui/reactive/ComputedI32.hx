package ashui.reactive;

import ashui.core.externs.BlincNative;

/** A computed `Int`, or an enum abstract over one; what `Computed.make` makes for those. **/
class ComputedI32 implements IComputed<Int> {
	public var ptr(default, null):hl.Abstract<"blinc_computed">;

	public function new(compute:Void->Int) {
		ptr = BlincNative.blinc_computed_i32(Guard.wrap(() -> BlincNative.blinc_return_i32(compute())));
		Owner.adoptComputed(ptr);
	}

	public function get():Int {
		var v = BlincNative.blinc_computed_get_i32(ptr);
		Guard.check();
		return v;
	}
}
