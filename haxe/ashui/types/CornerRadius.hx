package ashui.types;


class CornerRadius {
    public var ptr(default, null): hl.Abstract<"blinc_corner_radius">;

    public function new(topLeft: Single, topRight: Single, bottomRight: Single, bottomLeft: Single) {
        this.ptr = BlincTypesNative.hl_blinc_corner_radius_new(topLeft, topRight, bottomRight, bottomLeft);
        hl.Gc.setFinalizer(this, finalize);
    }

    public static inline function all(radius: Single): CornerRadius {
        return new CornerRadius(radius, radius, radius, radius);
    }

    static function finalize(obj: CornerRadius) {
        BlincTypesNative.hl_blinc_corner_radius_drop(obj.ptr);
    }
}