package ashui.reactive;

import ashui.core.externs.BlincNative;

class ComputedBool implements IComputed<Bool> {
	public var ptr(default, null):hl.Abstract<"blinc_computed">;

	public function new(compute:Void->Bool) {
		Guard.creating("A computed");
		ptr = BlincNative.blinc_computed_bool(Guard.wrap(() -> BlincNative.blinc_return_bool(compute() ? 1 : 0)));
		Owner.adoptComputed(ptr);
	}

	public function get():Bool {
		var v = BlincNative.blinc_computed_get_bool(ptr);
		Guard.check();
		return v;
	}
}
