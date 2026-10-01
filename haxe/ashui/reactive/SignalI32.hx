package ashui.reactive;

class SignalI32 implements ISignal<Int> {
	public var ptr(default, null):hl.Abstract<"blinc_sig_i32">;

	static var closureRegistry:Map<Int, Int->Int> = new Map();
	static var nextId:Int = 0;

	public function new(initialValue:Int) {
		this.ptr = BlincNative.hl_blinc_signal_new_i32(initialValue);
		hl.Gc.setFinalizer(this, finalize);
	}

	public inline function get():Int
		return BlincNative.hl_blinc_signal_get_i32(this.ptr);

	public inline function set(val:Int):Void
		BlincNative.hl_blinc_signal_set_i32(this.ptr, val);

	public function computed<R>(computeFn:Int->R):Computed<R> {
		var id = nextId++;
		// Erase type for the internal registry boundary
		closureRegistry.set(id, cast computeFn);
		var compPtr = BlincNative.hl_blinc_computed_i32(this.ptr, id, onComputeCallback);

		// The framework checks the return type R to instantiate the correct Computed wrapper
		// (Implementation of return routing handled in the macro layer or cast)
		return cast new ComputedI32(compPtr, id);
	}

	static function onComputeCallback(ctxId:Int, val:Int):Int {
		var closure = closureRegistry.get(ctxId);
		return closure != null ? closure(val) : val;
	}

	static function finalize(obj:SignalI32)
		BlincNative.hl_blinc_signal_drop_i32(obj.ptr);
}

class ComputedI32 implements ISignal.IComputed<Int> {
	public var ptr(default, null):hl.Abstract<"blinc_comp_i32">;

	var ctxId:Int;

	@:allow(reactive.SignalI32)
	function new(ptr:hl.Abstract<"blinc_comp_i32">, ctxId:Int) {
		this.ptr = ptr;
		this.ctxId = ctxId;
		hl.Gc.setFinalizer(this, finalize);
	}

	public inline function get():Int
		return BlincNative.hl_blinc_computed_get_i32(this.ptr);

	static function finalize(obj:ComputedI32) {
		BlincNative.hl_blinc_computed_drop_i32(obj.ptr);
		@:privateAccess SignalI32.closureRegistry.remove(obj.ctxId);
	}
}
