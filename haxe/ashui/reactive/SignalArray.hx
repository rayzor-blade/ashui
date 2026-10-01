package ashui.reactive;

class SignalArray<T> implements ISignal<Array<T>> {
    public var ptr(default, null): hl.Abstract<"blinc_sig_array">;
    
    @:keep private var _gcRoot: Array<T>; 
    static var closureRegistry: Map<Int, Array<T>->Array<T>> = new Map();
    static var nextId: Int = 0;

    public function new(initialValue: Array<T>) {
        this._gcRoot = initialValue;
        // Haxe's Array class wraps a NativeArray block internally.
        // We pass the raw contiguous varray to Rust.
        var nativeArray = @:privateAccess initialValue.__a;
        this.ptr = BlincNative.hl_blinc_signal_new_array(nativeArray);
        hl.Gc.setFinalizer(this, finalize);
    }

    public inline function get(): Array<T> {
        var nativeArray = BlincNative.hl_blinc_signal_get_array(this.ptr);
        return @:privateAccess Array.alloc(nativeArray); 
    }

    public inline function set(val: Array<T>): Void {
        this._gcRoot = val;
        var nativeArray = @:privateAccess val.__a;
        BlincNative.hl_blinc_signal_set_array(this.ptr, nativeArray);
    }
}