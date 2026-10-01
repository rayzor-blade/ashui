package ashui.reactive;

class SignalString implements ISignal<String> {
    public var ptr(default, null): hl.Abstract<"blinc_sig_bytes">;
    
    @:keep private var _gcRoot: String; // Root the full String object
    static var closureRegistry: Map<Int, String->String> = new Map();
    static var nextId: Int = 0;

    public function new(initialValue: String) {
        this._gcRoot = initialValue;
        // Pass the raw memory bytes, skipping vstring struct overhead
        this.ptr = BlincNative.hl_blinc_signal_new_bytes(initialValue.bytes); 
        hl.Gc.setFinalizer(this, finalize);
    }

    public inline function get(): String {
        var rawBytes = BlincNative.hl_blinc_signal_get_bytes(this.ptr);
        // Assumes you track length elsewhere, or rely on null-termination for UCS-2
        return String.fromUCS2(rawBytes); 
    }

    public inline function set(val: String): Void {
        this._gcRoot = val; 
        BlincNative.hl_blinc_signal_set_bytes(this.ptr, val.bytes);
    }

    // ... computed bindings mapping String <-> Bytes ...
}