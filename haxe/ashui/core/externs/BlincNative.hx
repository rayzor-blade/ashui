package ashui.core.externs;

@:hlNative("blinc_abi")
extern class BlincNative {
	// --- Dirty Flag / Render Loop ---
	public static function hl_blinc_is_dirty():Bool;
	public static function hl_blinc_clear_dirty():Void;

	// --- Int32 Signals ---
	public static function hl_blinc_signal_new_i32(initial:Int):hl.Abstract<"blinc_sig_i32">;
	public static function hl_blinc_signal_get_i32(sig:hl.Abstract<"blinc_sig_i32">):Int;
	public static function hl_blinc_signal_set_i32(sig:hl.Abstract<"blinc_sig_i32">, val:Int):Void;
	public static function hl_blinc_signal_drop_i32(sig:hl.Abstract<"blinc_sig_i32">):Void;

	public static function hl_blinc_computed_i32(parent:hl.Abstract<"blinc_sig_i32">, ctx_id:Int,
		compute_callback:(Int, Int) -> Int):hl.Abstract<"blinc_comp_i32">;

	public static function hl_blinc_computed_drop_i32(comp:hl.Abstract<"blinc_comp_i32">):Void;

	// --- Float32 Signals ---
	public static function hl_blinc_signal_new_f32(initial:Float):hl.Abstract<"blinc_sig_f32">;
	public static function hl_blinc_signal_get_f32(sig:hl.Abstract<"blinc_sig_f32">):Float;
	public static function hl_blinc_signal_set_f32(sig:hl.Abstract<"blinc_sig_f32">, val:Float):Void;
	public static function hl_blinc_signal_drop_f32(sig:hl.Abstract<"blinc_sig_f32">):Void;

	public static function hl_blinc_computed_f32(parent:hl.Abstract<"blinc_sig_f32">, ctx_id:Int,
		compute_callback:(Int, Float) -> Float):hl.Abstract<"blinc_comp_f32">;

	public static function hl_blinc_computed_drop_f32(comp:hl.Abstract<"blinc_comp_f32">):Void;

	// --- Float64 Signals ---
	public static function hl_blinc_signal_new_f64(initial:Float):hl.Abstract<"blinc_sig_f64">;
	public static function hl_blinc_signal_get_f64(sig:hl.Abstract<"blinc_sig_f64">):Float;
	public static function hl_blinc_signal_set_f64(sig:hl.Abstract<"blinc_sig_f64">, val:Float):Void;
	public static function hl_blinc_signal_drop_f64(sig:hl.Abstract<"blinc_sig_f64">):Void;

	public static function hl_blinc_computed_f64(parent:hl.Abstract<"blinc_sig_f64">, ctx_id:Int,
		compute_callback:(Int, Float) -> Float):hl.Abstract<"blinc_comp_f64">;

	public static function hl_blinc_computed_drop_f64(comp:hl.Abstract<"blinc_comp_f64">):Void;

	// --- Dynamic Signals (Opaque Haxe Objects) ---
	public static function hl_blinc_signal_new_dynamic(initial:Dynamic):hl.Abstract<"blinc_sig_dynamic">;
	public static function hl_blinc_signal_get_dynamic(sig:hl.Abstract<"blinc_sig_dynamic">):Dynamic;
	public static function hl_blinc_signal_set_dynamic(sig:hl.Abstract<"blinc_sig_dynamic">, val:Dynamic):Void;
	public static function hl_blinc_signal_drop_dynamic(sig:hl.Abstract<"blinc_sig_dynamic">):Void;

	public static function hl_blinc_computed_dynamic(parent:hl.Abstract<"blinc_sig_dynamic">, ctx_id:Int,
		compute_callback:(Int, Dynamic) -> Dynamic):hl.Abstract<"blinc_comp_dynamic">;

	public static function hl_blinc_computed_drop_dynamic(comp:hl.Abstract<"blinc_comp_dynamic">):Void;

	// Bytes
	public static function hl_blinc_signal_new_bytes(initial:hl.Bytes):hl.Abstract<"blinc_sig_bytes">;
	public static function hl_blinc_signal_get_bytes(sig:hl.Abstract<"blinc_sig_bytes">):hl.Bytes;
	public static function hl_blinc_signal_set_bytes(sig:hl.Abstract<"blinc_sig_bytes">, val:hl.Bytes):Void;
	public static function hl_blinc_signal_drop_bytes(sig:hl.Abstract<"blinc_sig_bytes">):Void;
	public static function hl_blinc_computed_bytes(parent:hl.Abstract<"blinc_sig_bytes">, ctx:Int,
		cb:(Int, hl.Bytes) -> hl.Bytes):hl.Abstract<"blinc_comp_bytes">;
	public static function hl_blinc_computed_drop_bytes(comp:hl.Abstract<"blinc_comp_bytes">):Void;

	// Arrays
	public static function hl_blinc_signal_new_array(initial:hl.NativeArray<Dynamic>):hl.Abstract<"blinc_sig_array">;
	public static function hl_blinc_signal_get_array(sig:hl.Abstract<"blinc_sig_array">):hl.NativeArray<Dynamic>;
	public static function hl_blinc_signal_set_array(sig:hl.Abstract<"blinc_sig_array">, val:hl.NativeArray<Dynamic>):Void;
	public static function hl_blinc_signal_drop_array(sig:hl.Abstract<"blinc_sig_array">):Void;
	public static function hl_blinc_computed_array(parent:hl.Abstract<"blinc_sig_array">, ctx:Int,
		cb:(Int, hl.NativeArray<Dynamic>) -> hl.NativeArray<Dynamic>):hl.Abstract<"blinc_comp_array">;
	public static function hl_blinc_computed_drop_array(comp:hl.Abstract<"blinc_comp_array">):Void;

	// ============================================================================
	// UNIFIED PROPERTY ROUTERS
	// ============================================================================
	// Signature: V_I64IIFPP
	public static function hl_blinc_apply_f32(node:haxe.Int64, prop:Int, kind:Int, val_const:Single, state_ptr:Dynamic, comp_ptr:Dynamic):Void;

	// Signature: V_I64IIIPP
	public static function hl_blinc_apply_i32(node:haxe.Int64, prop:Int, kind:Int, val_const:Int, state_ptr:Dynamic, comp_ptr:Dynamic):Void;

	// Signature: V_I64IIPPP (Note the extra 'P' because val_const is now a pointer)
	public static function hl_blinc_apply_brush(node:haxe.Int64, prop:Int, kind:Int, val_ptr:Dynamic, state_ptr:Dynamic, comp_ptr:Dynamic):Void;

	public static function hl_blinc_apply_color(node:haxe.Int64, prop:Int, kind:Int, val_ptr:Dynamic, state_ptr:Dynamic, comp_ptr:Dynamic):Void;

	public static function hl_blinc_apply_corner_radius(node:haxe.Int64, prop:Int, kind:Int, val_ptr:Dynamic, state_ptr:Dynamic, comp_ptr:Dynamic):Void;

	// ============================================================================
	// COMPLEX TYPE ALLOCATORS
	// ============================================================================
	// Brush
	public static function hl_blinc_brush_solid(hex:Int, alpha:Single):hl.Abstract<"blinc_brush">;
	public static function hl_blinc_brush_glass(blur:Single, tintHex:Int, tintAlpha:Single, simple:Bool):hl.Abstract<"blinc_brush">;
	public static function hl_blinc_brush_blur(radius:Single):hl.Abstract<"blinc_brush">;
	// Uses hl.Bytes for zero-copy string transfer
	public static function hl_blinc_brush_image(src:hl.Bytes, fit:Int):hl.Abstract<"blinc_brush">;

	public static function hl_blinc_brush_linear_gradient(sx:Single, sy:Single, ex:Single, ey:Single, fromHex:Int, fromAlpha:Single, toHex:Int,
		toAlpha:Single):hl.Abstract<"blinc_brush">;

	public static function hl_blinc_brush_drop(ptr:hl.Abstract<"blinc_brush">):Void;

	// Color
	public static function hl_blinc_color_new(r:Single, g:Single, b:Single, a:Single):hl.Abstract<"blinc_color">;
	public static function hl_blinc_color_drop(ptr:hl.Abstract<"blinc_color">):Void;

	// CornerRadius
	public static function hl_blinc_corner_radius_new(tl:Single, tr:Single, br:Single, bl:Single):hl.Abstract<"blinc_corner_radius">;
	public static function hl_blinc_corner_radius_drop(ptr:hl.Abstract<"blinc_corner_radius">):Void;

	public static function hl_blinc_apply_string(node:haxe.Int64, prop:Int, kind:Int, val_ptr:Dynamic, state_ptr:Dynamic, comp_ptr:Dynamic):Void;

	public static function hl_blinc_apply_transform(node:haxe.Int64, prop:Int, kind:Int, val_ptr:Dynamic, state_ptr:Dynamic, comp_ptr:Dynamic):Void;

	public static function hl_blinc_apply_shadow(node:haxe.Int64, prop:Int, kind:Int, val_ptr:Dynamic, state_ptr:Dynamic, comp_ptr:Dynamic):Void;
}
