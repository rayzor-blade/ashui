package ashui.types;

class Color {
    public var ptr(default, null): hl.Abstract<"blinc_color">;

    public function new(hex: Int, alpha: Single) {
        this.ptr = BlincTypesNative.hl_blinc_color_new(hex, alpha);
        hl.Gc.setFinalizer(this, finalize);
    }

    static function finalize(obj: Color) {
        BlincTypesNative.hl_blinc_color_drop(obj.ptr);
    }
}