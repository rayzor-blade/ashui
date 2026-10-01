
package ashui.types;

@:hlNative("blinc_abi")
extern class ShadowNative {
    public static function hl_blinc_shadow_new(offsetX: Single, offsetY: Single, blur: Single, hex: Int, alpha: Single): hl.Abstract<"blinc_shadow_vec">;
    public static function hl_blinc_shadow_drop(ptr: hl.Abstract<"blinc_shadow_vec">): Void;
}

class Shadow {
    public var ptr(default, null): hl.Abstract<"blinc_shadow_vec">;

    public function new(offsetX: Single, offsetY: Single, blur: Single, colorHex: Int, colorAlpha: Single = 1.0) {
        this.ptr = ShadowNative.hl_blinc_shadow_new(offsetX, offsetY, blur, colorHex, colorAlpha);
        hl.Gc.setFinalizer(this, finalize);
    }

    static function finalize(obj: Shadow) {
        ShadowNative.hl_blinc_shadow_drop(obj.ptr);
    }
}