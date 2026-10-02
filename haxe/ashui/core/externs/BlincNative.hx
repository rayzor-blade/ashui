package ashui.core.externs;

/**
	Signals, computeds, property routers and style values in `blinc_abi.hdll`.

	Handles are GC blocks the library allocates with a finalizer, so nothing
	here is freed by hand. Flags cross as `Int` rather than `Bool`.
**/
@:hlNative("blinc_abi")
extern class BlincNative {
	// --- Render loop ---
	static function blinc_is_dirty():Bool;
	static function blinc_clear_dirty():Void;

	// --- Int signals ---
	static function blinc_signal_i32(initial:Int):hl.Abstract<"blinc_signal">;
	static function blinc_signal_get_i32(sig:hl.Abstract<"blinc_signal">):Int;
	static function blinc_signal_set_i32(sig:hl.Abstract<"blinc_signal">, v:Int):Void;
	static function blinc_computed_i32(compute:Void->Void):hl.Abstract<"blinc_computed">;
	static function blinc_computed_get_i32(comp:hl.Abstract<"blinc_computed">):Int;
	static function blinc_return_i32(v:Int):Void;

	// --- Single signals ---
	static function blinc_signal_f32(initial:Single):hl.Abstract<"blinc_signal">;
	static function blinc_signal_get_f32(sig:hl.Abstract<"blinc_signal">):Single;
	static function blinc_signal_set_f32(sig:hl.Abstract<"blinc_signal">, v:Single):Void;
	static function blinc_computed_f32(compute:Void->Void):hl.Abstract<"blinc_computed">;
	static function blinc_computed_get_f32(comp:hl.Abstract<"blinc_computed">):Single;
	static function blinc_return_f32(v:Single):Void;

	// --- Float signals ---
	static function blinc_signal_f64(initial:Float):hl.Abstract<"blinc_signal">;
	static function blinc_signal_get_f64(sig:hl.Abstract<"blinc_signal">):Float;
	static function blinc_signal_set_f64(sig:hl.Abstract<"blinc_signal">, v:Float):Void;
	static function blinc_computed_f64(compute:Void->Void):hl.Abstract<"blinc_computed">;
	static function blinc_computed_get_f64(comp:hl.Abstract<"blinc_computed">):Float;
	static function blinc_return_f64(v:Float):Void;

	// --- Bool signals ---
	static function blinc_signal_bool(initial:Int):hl.Abstract<"blinc_signal">;
	static function blinc_signal_get_bool(sig:hl.Abstract<"blinc_signal">):Bool;
	static function blinc_signal_set_bool(sig:hl.Abstract<"blinc_signal">, v:Int):Void;
	static function blinc_computed_bool(compute:Void->Void):hl.Abstract<"blinc_computed">;
	static function blinc_computed_get_bool(comp:hl.Abstract<"blinc_computed">):Bool;
	static function blinc_return_bool(v:Int):Void;

	// --- String signals (NUL-terminated UTF-8) ---
	static function blinc_signal_string(initial:hl.Bytes):hl.Abstract<"blinc_signal">;
	static function blinc_signal_get_string(sig:hl.Abstract<"blinc_signal">):hl.Bytes;
	static function blinc_signal_set_string(sig:hl.Abstract<"blinc_signal">, v:hl.Bytes):Void;
	static function blinc_computed_string(compute:Void->Void):hl.Abstract<"blinc_computed">;
	static function blinc_computed_get_string(comp:hl.Abstract<"blinc_computed">):hl.Bytes;
	static function blinc_return_string(v:hl.Bytes):Void;

	// --- Value signals (brush, color, radius, transform, shadow) ---
	static function blinc_signal_value(initial:hl.Abstract<"blinc_value">):hl.Abstract<"blinc_signal">;
	static function blinc_signal_set_value(sig:hl.Abstract<"blinc_signal">, v:hl.Abstract<"blinc_value">):Void;
	static function blinc_computed_value(compute:Void->Void):hl.Abstract<"blinc_computed">;
	static function blinc_return_value(v:hl.Abstract<"blinc_value">):Void;

	// --- Any type ---
	static function blinc_signal_touch(sig:hl.Abstract<"blinc_signal">):Void;
	static function blinc_computed_touch(comp:hl.Abstract<"blinc_computed">):Void;
	/** Queues the computed for release at the next flush, before its handle is collected. **/
	static function blinc_computed_release(comp:hl.Abstract<"blinc_computed">):Void;

	// --- Property routers: kind 0 applies `constant`, 1 binds `sig`, 2 binds `comp` ---
	static function blinc_apply_f32(node:haxe.Int64, prop:Int, kind:Int, constant:Single, sig:hl.Abstract<"blinc_signal">,
		comp:hl.Abstract<"blinc_computed">):Void;
	static function blinc_apply_i32(node:haxe.Int64, prop:Int, kind:Int, constant:Int, sig:hl.Abstract<"blinc_signal">,
		comp:hl.Abstract<"blinc_computed">):Void;
	static function blinc_apply_value(node:haxe.Int64, prop:Int, kind:Int, constant:hl.Abstract<"blinc_value">, sig:hl.Abstract<"blinc_signal">,
		comp:hl.Abstract<"blinc_computed">):Void;
	static function blinc_apply_string(node:haxe.Int64, prop:Int, kind:Int, constant:hl.Bytes, sig:hl.Abstract<"blinc_signal">,
		comp:hl.Abstract<"blinc_computed">):Void;

	// --- Style values ---
	static function blinc_brush_solid(hex:Int, alpha:Single):hl.Abstract<"blinc_value">;
	static function blinc_brush_glass(blur:Single, tintHex:Int, tintAlpha:Single, simple:Int):hl.Abstract<"blinc_value">;
	static function blinc_brush_blur(radius:Single):hl.Abstract<"blinc_value">;
	static function blinc_brush_image(src:hl.Bytes, fit:Int):hl.Abstract<"blinc_value">;
	static function blinc_brush_linear_gradient(sx:Single, sy:Single, ex:Single, ey:Single, fromHex:Int, fromAlpha:Single, toHex:Int,
		toAlpha:Single):hl.Abstract<"blinc_value">;
	static function blinc_color_hex(hex:Int, alpha:Single):hl.Abstract<"blinc_value">;
	static function blinc_corner_radius(tl:Single, tr:Single, br:Single, bl:Single):hl.Abstract<"blinc_value">;
	static function blinc_transform_identity():hl.Abstract<"blinc_value">;
	static function blinc_transform_translate(x:Single, y:Single):hl.Abstract<"blinc_value">;
	static function blinc_shadow(offsetX:Single, offsetY:Single, blur:Single, hex:Int, alpha:Single):hl.Abstract<"blinc_value">;
}
