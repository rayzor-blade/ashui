package ashui.core.externs;

/**
	The reactive graph and style values of the native library,
	`blinc_abi.hdll`. A signal holds a value and notifies whatever read it
	when it is set; a computed derives a value from signals and is
	recomputed when they change; its `compute` callback hands its result
	back through the matching `blinc_return_*`. An effect is a callback
	re-run the same way. A property router binds a layout node's property
	to a constant, a signal or a computed. Style values (brushes, colours, radii, transforms,
	shadows, clip paths) are immutable handles a node's properties take.
	`ashui.reactive` and `ashui.types` wrap all of this; app code uses those.

	Handles are GC blocks the library allocates with a finalizer, so nothing
	here is freed by hand. Flags cross as `Int` rather than `Bool`.
**/
@:hlNative("blinc_abi")
extern class BlincNative {
	// --- Render loop: whether any signal changed since the last clear ---
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

	// --- Any type: `touch` reads it, so the computed or effect running depends on it ---
	static function blinc_signal_touch(sig:hl.Abstract<"blinc_signal">):Void;
	static function blinc_computed_touch(comp:hl.Abstract<"blinc_computed">):Void;
	/** Queues the computed for release at the next flush, before its handle is collected. **/
	static function blinc_computed_release(comp:hl.Abstract<"blinc_computed">):Void;

	// --- Effects: `run` runs now and again whenever a signal or computed it read changes ---
	static function blinc_effect(run:Void->Void):hl.Abstract<"blinc_effect">;
	/** Stops the effect; it is removed at the next flush. **/
	static function blinc_effect_release(effect:hl.Abstract<"blinc_effect">):Void;

	// --- Host-run effects: Haxe runs the body, and what it reads between begin and end is what it depends on ---
	/** A new host effect's slot; it starts due, and its first run is the caller's. **/
	static function blinc_host_effect_new():Int;
	/** Writes up to `capacity` due slots into `out`, as 32-bit ints; how many. **/
	static function blinc_host_effects_due(out:hl.Bytes, capacity:Int):Int;
	static function blinc_host_effect_begin(slot:Int):Bool;
	/** Ends the body and applies the signal writes it made; called on every way out of it. **/
	static function blinc_host_effect_end(slot:Int):Void;
	/** Stops the effect; the slot may name another, and it is removed from the graph at the next flush. **/
	static function blinc_host_effect_release(slot:Int):Void;

	// --- Property routers: kind 0 applies `constant`, 1 binds `sig`, 2 binds `comp` ---
	static function blinc_apply_f32(node:haxe.Int64, prop:Int, kind:Int, constant:Single, sig:hl.Abstract<"blinc_signal">,
		comp:hl.Abstract<"blinc_computed">):Void;
	static function blinc_apply_i32(node:haxe.Int64, prop:Int, kind:Int, constant:Int, sig:hl.Abstract<"blinc_signal">,
		comp:hl.Abstract<"blinc_computed">):Void;
	static function blinc_apply_value(node:haxe.Int64, prop:Int, kind:Int, constant:hl.Abstract<"blinc_value">, sig:hl.Abstract<"blinc_signal">,
		comp:hl.Abstract<"blinc_computed">):Void;
	static function blinc_apply_string(node:haxe.Int64, prop:Int, kind:Int, constant:hl.Bytes, sig:hl.Abstract<"blinc_signal">,
		comp:hl.Abstract<"blinc_computed">):Void;

	/**
		Puts property `prop` (a `PropertyId`, or `Node.CORNER_SHAPE`) of
		`node` back to a new node's value; a percentage or per-side id resets
		the field it writes.
	**/
	static function blinc_unset(node:haxe.Int64, prop:Int):Void;

	// --- Style values ---
	static function blinc_brush_solid(hex:Int, alpha:Single):hl.Abstract<"blinc_value">;
	static function blinc_brush_glass(blur:Single, tintHex:Int, tintAlpha:Single, simple:Int, noise:Single):hl.Abstract<"blinc_value">;
	static function blinc_brush_glass_aberration(brush:hl.Abstract<"blinc_value">, strength:Single):Void;
	static function blinc_brush_glass_bevel(brush:hl.Abstract<"blinc_value">, strength:Single, inset:Bool):Void;
	static function blinc_brush_blur(radius:Single, tintHex:Int, tintAlpha:Single):hl.Abstract<"blinc_value">;
	static function blinc_brush_image(src:hl.Bytes, fit:Int):hl.Abstract<"blinc_value">;
	static function blinc_brush_linear_gradient(sx:Single, sy:Single, ex:Single, ey:Single, fromHex:Int, fromAlpha:Single, toHex:Int,
		toAlpha:Single):hl.Abstract<"blinc_value">;
	static function blinc_color_hex(hex:Int, alpha:Single):hl.Abstract<"blinc_value">;
	static function blinc_corner_radius(tl:Single, tr:Single, br:Single, bl:Single):hl.Abstract<"blinc_value">;
	static function blinc_transform_identity():hl.Abstract<"blinc_value">;
	static function blinc_transform_translate(x:Single, y:Single):hl.Abstract<"blinc_value">;
	static function blinc_brush_gradient(radial:Bool, x1:Single, y1:Single, x2:Single, y2:Single, bbox:Bool):hl.Abstract<"blinc_value">;
	static function blinc_brush_gradient_stop(brush:hl.Abstract<"blinc_value">, offset:Single, hex:Int, alpha:Single):Void;
	static function blinc_transform_affine(a:Single, b:Single, c:Single, d:Single, tx:Single, ty:Single):hl.Abstract<"blinc_value">;
	static function blinc_corner_shape(topLeft:Single, topRight:Single, bottomRight:Single, bottomLeft:Single, locked:Bool):hl.Abstract<"blinc_value">;
	static function blinc_shadow(offsetX:Single, offsetY:Single, blur:Single, spread:Single, hex:Int, alpha:Single, inset:Bool):hl.Abstract<"blinc_value">;

	/**
		A clip-path shape: `kind` 0 circle, 1 ellipse, 2 inset, 3 rect, 4
		xywh, -1 none. `values` holds its lengths as F32s, each a percentage
		where its bit in `percent` is set and left out where its bit in
		`none` is; `round` is the corner radius, or -1. See `ClipPath`.
	**/
	static function blinc_clip_path(kind:Int, values:hl.Bytes, percent:Int, none:Int, round:Single):hl.Abstract<"blinc_value">;

	/** A polygon clip path, `count` points of x and y in `values`, each a percentage where its byte in `percent` is 1; a path's are pixels, rings apart by a 1e30 point. **/
	static function blinc_clip_polygon(values:hl.Bytes, percent:hl.Bytes, count:Int, path:Bool):hl.Abstract<"blinc_value">;
	static function blinc_shadow_push(shadow:hl.Abstract<"blinc_value">, offsetX:Single, offsetY:Single, blur:Single, spread:Single, hex:Int,
		alpha:Single, inset:Bool):Void;
}
