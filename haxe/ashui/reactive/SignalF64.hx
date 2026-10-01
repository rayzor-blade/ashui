package ashui.reactive;

class SignalF64 implements ISignal<Float> {
    public var ptr(default, null):hl.Abstract<"blinc_sig_f64">;

    static var closureRegistry:Map<Float, Float->Float> = new Map();
    static var nextId:Int = 0;

    public function new(initialValue:Float) {
        this.ptr = BlincNative.hl_blinc_signal_new_f64(initialValue);
        hl.Gc.setFinalizer(this, finalize);
    }

    public inline function get():Float
        return BlincNative.hl_blinc_signal_get_f64(this.ptr);

    public inline function set(val:Float):Void
        BlincNative.hl_blinc_signal_set_f64(this.ptr, val);

    public function computed<R>(computeFn:Float->R):Computed<R> {
        var id = nextId++;
        // Erase type for the internal registry boundary
        closureRegistry.set(id, cast computeFn);
        var compPtr = BlincNative.hl_blinc_computed_f64(this.ptr, id, onComputeCallback);

        // The framework checks the return type R to instantiate the correct Computed wrapper
        // (Implementation of return routing handled in the macro layer or cast)
        return cast new ComputedF64(compPtr, id);
    }

    static function onComputeCallback(ctxId:Int, val:Float):Float {
        var closure = closureRegistry.get(ctxId);
        return closure != null ? closure(val) : val;
    }

    static function finalize(obj:SignalF64)
        BlincNative.hl_blinc_signal_drop_f64(obj.ptr);
}