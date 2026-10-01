package ashui.types;


@:hlNative("blinc_abi")
extern class TransformNative {
    public static function hl_blinc_transform_identity(): hl.Abstract<"blinc_transform">;
    public static function hl_blinc_transform_translation(x: Single, y: Single): hl.Abstract<"blinc_transform">;
    public static function hl_blinc_transform_drop(ptr: hl.Abstract<"blinc_transform">): Void;
}

class Transform {
    public var ptr(default, null): hl.Abstract<"blinc_transform">;

    public function new(ptr: hl.Abstract<"blinc_transform">) {
        this.ptr = ptr;
        hl.Gc.setFinalizer(this, finalize);
    }

    public static inline function identity(): Transform {
        return new Transform(TransformNative.hl_blinc_transform_identity());
    }

    public static inline function translation(x: Single, y: Single): Transform {
        return new Transform(TransformNative.hl_blinc_transform_translation(x, y));
    }

    static function finalize(obj: Transform) {
        TransformNative.hl_blinc_transform_drop(obj.ptr);
    }
}