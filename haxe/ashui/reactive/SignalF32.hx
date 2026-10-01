package ashui.reactive;

class SignalF32 implements ISignal<Float> {
	public var ptr(default, null):hl.Abstract<"blinc_sig_f32">;

	static var closureRegistry:Map<Float, Float->Float> = new Map();
	static var nextId:Int = 0;

	public function new(initialValue:Float) {
		this.ptr = BlincNative.hl_blinc_signal_new_f32(initialValue);
		hl.Gc.setFinalizer(this, finalize);
	}

	public inline function get():Float
		return BlincNative.hl_blinc_signal_get_f32(this.ptr);

	public inline function set(val:Float):Void
		BlincNative.hl_blinc_signal_set_f32(this.ptr, val);

	public function computed<R>(computeFn:Float->R):Computed<R> {
		var id = nextId++;
		// Erase type for the internal registry boundary
		closureRegistry.set(id, cast computeFn);
		var compPtr = BlincNative.hl_blinc_computed_f32(this.ptr, id, onComputeCallback);

		// The framework checks the return type R to instantiate the correct Computed wrapper
		// (Implementation of return routing handled in the macro layer or cast)
		return cast new ComputedF32(compPtr, id);
	}

	static function onComputeCallback(ctxId:Int, val:Float):Float {
		var closure = closureRegistry.get(ctxId);
		return closure != null ? closure(val) : val;
	}

	static function finalize(obj:SignalF32)
		BlincNative.hl_blinc_signal_drop_f32(obj.ptr);
}

class ComputedF32 implements ISignal.IComputed<Float> {
	public var ptr(default, null):hl.Abstract<"blinc_comp_f32">;

	var ctxId:Int;

	@:allow(reactive.SignalF32)
	function new(ptr:hl.Abstract<"blinc_comp_f32">, ctxId:Int) {
		this.ptr = ptr;
		this.ctxId = ctxId;
		hl.Gc.setFinalizer(this, finalize);
	}

	public inline function get():Float
		return BlincNative.hl_blinc_computed_get_f32(this.ptr);

	static function finalize(obj:ComputedF32) {
		BlincNative.hl_blinc_computed_drop_f32(obj.ptr);
		@:privateAccess SignalF32.closureRegistry.remove(obj.ctxId);
	}
}
