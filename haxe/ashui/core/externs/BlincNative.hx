package ashui.core.externs;

import ashui.core.externs.Handles;

#if ashui_caribou
/**
	`BlincNative` over the `blinc_abi` Caribou plugin: the same calls, made on
	its `Signal`, `Computed`, `Effects` and `StyleValue` classes. A computed's
	callback hands its result back through `blinc_return_*`, kept here until
	the plugin's callback returns it.
**/
class BlincNative {
	static var retInt = 0;
	static var retFloat = 0.0;
	static var retBool = false;
	static var retString:String = null;

	/** The tree the plugin's property writes go through; the nodes belong to the one shared tree. **/
	static var router:blinc_abi.Tree;

	static inline function tree():blinc_abi.Tree {
		if (router == null)
			router = new blinc_abi.Tree();
		return router;
	}

	static inline function text(b:hl.Bytes):String
		return b == null ? "" : @:privateAccess String.fromUTF8(b);

	static inline function bytes(s:String):hl.Bytes
		return s == null ? null : @:privateAccess s.toUtf8();

	static inline function wrap(b:hl.Bytes, length:Int):haxe.io.Bytes
		return b == null ? haxe.io.Bytes.alloc(0) : @:privateAccess new haxe.io.Bytes(b, length);

	public static inline function blinc_is_dirty():Bool
		return blinc_abi.Effects.is_dirty();

	public static inline function blinc_clear_dirty():Void
		blinc_abi.Effects.clear_dirty();

	// --- Int signals ---
	public static inline function blinc_signal_i32(initial:Int):SignalHandle
		return blinc_abi.Signal.int(initial);

	public static inline function blinc_signal_get_i32(sig:SignalHandle):Int
		return sig.get_int();

	public static inline function blinc_signal_set_i32(sig:SignalHandle, v:Int):Void
		sig.set_int(v);

	public static function blinc_computed_i32(compute:Void->Void):ComputedHandle
		return blinc_abi.Computed.int(() -> {
			retInt = 0;
			compute();
			return retInt;
		});

	public static inline function blinc_computed_get_i32(comp:ComputedHandle):Int
		return comp.get_int();

	public static inline function blinc_return_i32(v:Int):Void
		retInt = v;

	// --- Single signals ---
	public static inline function blinc_signal_f32(initial:Single):SignalHandle
		return blinc_abi.Signal.float(initial);

	public static inline function blinc_signal_get_f32(sig:SignalHandle):Single
		return sig.get_float();

	public static inline function blinc_signal_set_f32(sig:SignalHandle, v:Single):Void
		sig.set_float(v);

	public static function blinc_computed_f32(compute:Void->Void):ComputedHandle
		return blinc_abi.Computed.float(() -> {
			retFloat = 0;
			compute();
			return retFloat;
		});

	public static inline function blinc_computed_get_f32(comp:ComputedHandle):Single
		return comp.get_float();

	public static inline function blinc_return_f32(v:Single):Void
		retFloat = v;

	// --- Float signals ---
	public static inline function blinc_signal_f64(initial:Float):SignalHandle
		return blinc_abi.Signal.double(initial);

	public static inline function blinc_signal_get_f64(sig:SignalHandle):Float
		return sig.get_double();

	public static inline function blinc_signal_set_f64(sig:SignalHandle, v:Float):Void
		sig.set_double(v);

	public static function blinc_computed_f64(compute:Void->Void):ComputedHandle
		return blinc_abi.Computed.double(() -> {
			retFloat = 0;
			compute();
			return retFloat;
		});

	public static inline function blinc_computed_get_f64(comp:ComputedHandle):Float
		return comp.get_double();

	public static inline function blinc_return_f64(v:Float):Void
		retFloat = v;

	// --- Bool signals ---
	public static inline function blinc_signal_bool(initial:Int):SignalHandle
		return blinc_abi.Signal.bool(initial != 0);

	public static inline function blinc_signal_get_bool(sig:SignalHandle):Bool
		return sig.get_bool();

	public static inline function blinc_signal_set_bool(sig:SignalHandle, v:Int):Void
		sig.set_bool(v != 0);

	public static function blinc_computed_bool(compute:Void->Void):ComputedHandle
		return blinc_abi.Computed.bool(() -> {
			retBool = false;
			compute();
			return retBool;
		});

	public static inline function blinc_computed_get_bool(comp:ComputedHandle):Bool
		return comp.get_bool();

	public static inline function blinc_return_bool(v:Int):Void
		retBool = v != 0;

	// --- String signals ---
	public static function blinc_signal_string(initial:hl.Bytes):SignalHandle
		return initial == null ? blinc_abi.Signal.none() : blinc_abi.Signal.text(text(initial));

	public static function blinc_signal_get_string(sig:SignalHandle):hl.Bytes
		return sig.has_text() ? bytes(sig.get_text()) : null;

	public static function blinc_signal_set_string(sig:SignalHandle, v:hl.Bytes):Void {
		if (v == null)
			sig.set_none();
		else
			sig.set_text(text(v));
	}

	public static inline function blinc_signal_string_version(sig:SignalHandle):Int
		return sig.text_version();

	public static function blinc_computed_string(compute:Void->Void):ComputedHandle
		return blinc_abi.Computed.text(() -> {
			retString = null;
			compute();
			return retString;
		});

	public static function blinc_computed_get_string(comp:ComputedHandle):hl.Bytes
		return comp.has_text() ? bytes(comp.get_text()) : null;

	public static function blinc_return_string(v:hl.Bytes):Void
		retString = v == null ? null : text(v);

	// --- Value signals ---
	public static inline function blinc_signal_value(initial:ValueHandle):SignalHandle
		return blinc_abi.Signal.value(initial);

	public static inline function blinc_signal_set_value(sig:SignalHandle, v:ValueHandle):Void
		sig.set_value(v);

	public static inline function blinc_computed_value(compute:Void->Void):ComputedHandle
		return blinc_abi.Computed.value(compute);

	public static inline function blinc_return_value(v:ValueHandle):Void
		blinc_abi.Computed.return_value(v);

	// --- Any type ---
	public static inline function blinc_signal_touch(sig:SignalHandle):Void
		sig.touch();

	public static inline function blinc_computed_touch(comp:ComputedHandle):Void
		comp.touch();

	public static inline function blinc_computed_release(comp:ComputedHandle):Void
		comp.release();

	// --- Host-run effects ---
	public static inline function blinc_host_effect_new():Int
		return blinc_abi.Effects.create();

	public static inline function blinc_host_effects_due(out:hl.Bytes, capacity:Int):Int
		return blinc_abi.Effects.due(wrap(out, capacity * 4));

	public static inline function blinc_host_effect_begin(slot:Int):Bool
		return blinc_abi.Effects.begin(slot);

	public static inline function blinc_host_effect_end(slot:Int):Void
		blinc_abi.Effects.end(slot);

	public static inline function blinc_host_effect_release(slot:Int):Void
		blinc_abi.Effects.release(slot);

	// --- Property routers ---
	public static function blinc_apply_f32(node:haxe.Int64, prop:Int, kind:Int, constant:Single, sig:SignalHandle, comp:ComputedHandle):Void {
		switch (kind) {
			case 0: tree().apply_f32(node, prop, constant);
			case 1: tree().bind_f32(node, prop, sig);
			default: tree().bind_f32_computed(node, prop, comp);
		}
	}

	public static function blinc_apply_i32(node:haxe.Int64, prop:Int, kind:Int, constant:Int, sig:SignalHandle, comp:ComputedHandle):Void {
		switch (kind) {
			case 0: tree().apply_i32(node, prop, constant);
			case 1: tree().bind_i32(node, prop, sig);
			default: tree().bind_i32_computed(node, prop, comp);
		}
	}

	public static function blinc_apply_value(node:haxe.Int64, prop:Int, kind:Int, constant:ValueHandle, sig:SignalHandle, comp:ComputedHandle):Void {
		switch (kind) {
			case 0: tree().apply_value(node, prop, constant);
			case 1: tree().bind_value(node, prop, sig);
			default: tree().bind_value_computed(node, prop, comp);
		}
	}

	public static function blinc_apply_string(node:haxe.Int64, prop:Int, kind:Int, constant:hl.Bytes, sig:SignalHandle, comp:ComputedHandle):Void {
		switch (kind) {
			case 0: tree().apply_string(node, prop, text(constant));
			case 1: tree().bind_string(node, prop, sig);
			default: tree().bind_string_computed(node, prop, comp);
		}
	}

	public static inline function blinc_unset(node:haxe.Int64, prop:Int):Void
		tree().unset(node, prop);

	// --- Style values ---
	public static inline function blinc_brush_solid(hex:Int, alpha:Single):ValueHandle
		return blinc_abi.StyleValue.brush_solid(hex, alpha);

	public static inline function blinc_brush_glass(blur:Single, tintHex:Int, tintAlpha:Single, simple:Int, noise:Single):ValueHandle
		return blinc_abi.StyleValue.brush_glass(blur, tintHex, tintAlpha, simple, noise);

	public static inline function blinc_brush_glass_aberration(brush:ValueHandle, strength:Single):Void
		brush.glass_aberration(strength);

	public static inline function blinc_brush_glass_bevel(brush:ValueHandle, strength:Single, inset:Bool):Void
		brush.glass_bevel(strength, inset);

	public static inline function blinc_brush_blur(radius:Single, tintHex:Int, tintAlpha:Single):ValueHandle
		return blinc_abi.StyleValue.brush_blur(radius, tintHex, tintAlpha);

	public static inline function blinc_brush_image(src:hl.Bytes, fit:Int):ValueHandle
		return blinc_abi.StyleValue.brush_image(text(src), fit);

	public static inline function blinc_brush_image_mapping(brush:ValueHandle, x:Single, y:Single, offsetX:Single, offsetY:Single, repeat:Int):Void
		brush.brush_image_mapping(x, y, offsetX, offsetY, repeat);

	public static inline function blinc_brush_linear_gradient(sx:Single, sy:Single, ex:Single, ey:Single, fromHex:Int, fromAlpha:Single, toHex:Int,
			toAlpha:Single):ValueHandle
		return blinc_abi.StyleValue.brush_linear_gradient(sx, sy, ex, ey, fromHex, fromAlpha, toHex, toAlpha);

	public static inline function blinc_color_hex(hex:Int, alpha:Single):ValueHandle
		return blinc_abi.StyleValue.color(hex, alpha);

	public static inline function blinc_corner_radius(tl:Single, tr:Single, br:Single, bl:Single):ValueHandle
		return blinc_abi.StyleValue.corner_radius(tl, tr, br, bl);

	public static inline function blinc_transform_identity():ValueHandle
		return blinc_abi.StyleValue.transform_identity();

	public static inline function blinc_transform_translate(x:Single, y:Single):ValueHandle
		return blinc_abi.StyleValue.transform_translate(x, y);

	public static inline function blinc_brush_gradient(radial:Bool, x1:Single, y1:Single, x2:Single, y2:Single, bbox:Bool):ValueHandle
		return blinc_abi.StyleValue.brush_gradient(radial, x1, y1, x2, y2, bbox);

	public static inline function blinc_brush_gradient_stop(brush:ValueHandle, offset:Single, hex:Int, alpha:Single):Void
		brush.gradient_stop(offset, hex, alpha);

	public static inline function blinc_transform_affine(a:Single, b:Single, c:Single, d:Single, tx:Single, ty:Single):ValueHandle
		return blinc_abi.StyleValue.transform_affine(a, b, c, d, tx, ty);

	public static inline function blinc_corner_shape(topLeft:Single, topRight:Single, bottomRight:Single, bottomLeft:Single, locked:Bool):ValueHandle
		return blinc_abi.StyleValue.corner_shape(topLeft, topRight, bottomRight, bottomLeft, locked);

	public static inline function blinc_shadow(offsetX:Single, offsetY:Single, blur:Single, spread:Single, hex:Int, alpha:Single, inset:Bool):ValueHandle
		return blinc_abi.StyleValue.shadow(offsetX, offsetY, blur, spread, hex, alpha, inset);

	public static inline function blinc_clip_path(kind:Int, values:hl.Bytes, percent:Int, none:Int, round:Single):ValueHandle
		return blinc_abi.StyleValue.clip_path(kind, wrap(values, 16), percent, none, round);

	public static inline function blinc_clip_polygon(values:hl.Bytes, percent:hl.Bytes, count:Int, path:Bool):ValueHandle
		return blinc_abi.StyleValue.clip_polygon(wrap(values, count * 8), wrap(percent, count * 2), count, path);

	public static inline function blinc_clip_even_odd(clip:ValueHandle):ValueHandle
		return clip.clip_even_odd();

	public static inline function blinc_shadow_push(shadow:ValueHandle, offsetX:Single, offsetY:Single, blur:Single, spread:Single, hex:Int, alpha:Single,
			inset:Bool):Void
		shadow.shadow_push(offsetX, offsetY, blur, spread, hex, alpha, inset);

	public static inline function blinc_text_decoration(lines:Int, style:Int, hex:Int, alpha:Single, thickness:Single, offset:Single):ValueHandle
		return blinc_abi.StyleValue.text_decoration(lines, style, hex, alpha, thickness, offset);
}
#else
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
	static function blinc_signal_i32(initial:Int):SignalHandle;
	static function blinc_signal_get_i32(sig:SignalHandle):Int;
	static function blinc_signal_set_i32(sig:SignalHandle, v:Int):Void;
	static function blinc_computed_i32(compute:Void->Void):ComputedHandle;
	static function blinc_computed_get_i32(comp:ComputedHandle):Int;
	static function blinc_return_i32(v:Int):Void;

	// --- Single signals ---
	static function blinc_signal_f32(initial:Single):SignalHandle;
	static function blinc_signal_get_f32(sig:SignalHandle):Single;
	static function blinc_signal_set_f32(sig:SignalHandle, v:Single):Void;
	static function blinc_computed_f32(compute:Void->Void):ComputedHandle;
	static function blinc_computed_get_f32(comp:ComputedHandle):Single;
	static function blinc_return_f32(v:Single):Void;

	// --- Float signals ---
	static function blinc_signal_f64(initial:Float):SignalHandle;
	static function blinc_signal_get_f64(sig:SignalHandle):Float;
	static function blinc_signal_set_f64(sig:SignalHandle, v:Float):Void;
	static function blinc_computed_f64(compute:Void->Void):ComputedHandle;
	static function blinc_computed_get_f64(comp:ComputedHandle):Float;
	static function blinc_return_f64(v:Float):Void;

	// --- Bool signals ---
	static function blinc_signal_bool(initial:Int):SignalHandle;
	static function blinc_signal_get_bool(sig:SignalHandle):Bool;
	static function blinc_signal_set_bool(sig:SignalHandle, v:Int):Void;
	static function blinc_computed_bool(compute:Void->Void):ComputedHandle;
	static function blinc_computed_get_bool(comp:ComputedHandle):Bool;
	static function blinc_return_bool(v:Int):Void;

	// --- String signals (NUL-terminated UTF-8) ---
	static function blinc_signal_string(initial:hl.Bytes):SignalHandle;
	static function blinc_signal_get_string(sig:SignalHandle):hl.Bytes;
	static function blinc_signal_set_string(sig:SignalHandle, v:hl.Bytes):Void;
	/** Bumps on every `set`; untracked. Lets a reader skip re-decoding an unchanged value. **/
	static function blinc_signal_string_version(sig:SignalHandle):Int;
	static function blinc_computed_string(compute:Void->Void):ComputedHandle;
	static function blinc_computed_get_string(comp:ComputedHandle):hl.Bytes;
	static function blinc_return_string(v:hl.Bytes):Void;

	// --- Value signals (brush, color, radius, transform, shadow) ---
	static function blinc_signal_value(initial:ValueHandle):SignalHandle;
	static function blinc_signal_set_value(sig:SignalHandle, v:ValueHandle):Void;
	static function blinc_computed_value(compute:Void->Void):ComputedHandle;
	static function blinc_return_value(v:ValueHandle):Void;

	// --- Any type: `touch` reads it, so the computed or effect running depends on it ---
	static function blinc_signal_touch(sig:SignalHandle):Void;
	static function blinc_computed_touch(comp:ComputedHandle):Void;

	/** Queues the computed for release at the next flush, before its handle is collected. **/
	static function blinc_computed_release(comp:ComputedHandle):Void;

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
	static function blinc_apply_f32(node:haxe.Int64, prop:Int, kind:Int, constant:Single, sig:SignalHandle,
		comp:ComputedHandle):Void;
	static function blinc_apply_i32(node:haxe.Int64, prop:Int, kind:Int, constant:Int, sig:SignalHandle,
		comp:ComputedHandle):Void;
	static function blinc_apply_value(node:haxe.Int64, prop:Int, kind:Int, constant:ValueHandle, sig:SignalHandle,
		comp:ComputedHandle):Void;
	static function blinc_apply_string(node:haxe.Int64, prop:Int, kind:Int, constant:hl.Bytes, sig:SignalHandle,
		comp:ComputedHandle):Void;

	/**
		Puts property `prop` (a `PropertyId`, or `Node.CORNER_SHAPE`) of
		`node` back to a new node's value; a percentage or per-side id resets
		the field it writes.
	**/
	static function blinc_unset(node:haxe.Int64, prop:Int):Void;

	// --- Style values ---
	static function blinc_brush_solid(hex:Int, alpha:Single):ValueHandle;
	static function blinc_brush_glass(blur:Single, tintHex:Int, tintAlpha:Single, simple:Int, noise:Single):ValueHandle;
	static function blinc_brush_glass_aberration(brush:ValueHandle, strength:Single):Void;
	static function blinc_brush_glass_bevel(brush:ValueHandle, strength:Single, inset:Bool):Void;
	static function blinc_brush_blur(radius:Single, tintHex:Int, tintAlpha:Single):ValueHandle;
	static function blinc_brush_image(src:hl.Bytes, fit:Int):ValueHandle;
	static function blinc_brush_image_mapping(brush:ValueHandle, x:Single, y:Single, offsetX:Single, offsetY:Single, repeat:Int):Void;
	static function blinc_brush_linear_gradient(sx:Single, sy:Single, ex:Single, ey:Single, fromHex:Int, fromAlpha:Single, toHex:Int,
		toAlpha:Single):ValueHandle;
	static function blinc_color_hex(hex:Int, alpha:Single):ValueHandle;
	static function blinc_corner_radius(tl:Single, tr:Single, br:Single, bl:Single):ValueHandle;
	static function blinc_transform_identity():ValueHandle;
	static function blinc_transform_translate(x:Single, y:Single):ValueHandle;
	static function blinc_brush_gradient(radial:Bool, x1:Single, y1:Single, x2:Single, y2:Single, bbox:Bool):ValueHandle;
	static function blinc_brush_gradient_stop(brush:ValueHandle, offset:Single, hex:Int, alpha:Single):Void;
	static function blinc_transform_affine(a:Single, b:Single, c:Single, d:Single, tx:Single, ty:Single):ValueHandle;
	static function blinc_corner_shape(topLeft:Single, topRight:Single, bottomRight:Single, bottomLeft:Single, locked:Bool):ValueHandle;
	static function blinc_shadow(offsetX:Single, offsetY:Single, blur:Single, spread:Single, hex:Int, alpha:Single, inset:Bool):ValueHandle;

	/**
		A clip-path shape: `kind` 0 circle, 1 ellipse, 2 inset, 3 rect, 4
		xywh, -1 none. `values` holds its lengths as F32s, each a percentage
		where its bit in `percent` is set and left out where its bit in
		`none` is; `round` is the corner radius, or -1. See `ClipPath`.
	**/
	static function blinc_clip_path(kind:Int, values:hl.Bytes, percent:Int, none:Int, round:Single):ValueHandle;

	/** A polygon clip path, `count` points of x and y in `values`, each a percentage where its byte in `percent` is 1; a path's are pixels, rings apart by a 1e30 point. **/
	static function blinc_clip_polygon(values:hl.Bytes, percent:hl.Bytes, count:Int, path:Bool):ValueHandle;

	/** A clip-path value filling by the even-odd rule, from a polygon or path one; null for another shape. **/
	static function blinc_clip_even_odd(clip:ValueHandle):ValueHandle;

	static function blinc_shadow_push(shadow:ValueHandle, offsetX:Single, offsetY:Single, blur:Single, spread:Single, hex:Int, alpha:Single,
		inset:Bool):Void;

	/**
		A text decoration: `lines` is `UNDERLINE` (1), `OVERLINE` (2) and
		`LINE_THROUGH` (4) as bits; `style` is 0 solid, 1 double, 2 dotted, 3
		dashed. A negative `alpha` is no colour of its own, the text's; a NaN
		`thickness` or `offset` is the font's own. See `TextDecoration`.
	**/
	static function blinc_text_decoration(lines:Int, style:Int, hex:Int, alpha:Single, thickness:Single, offset:Single):ValueHandle;
}
#end
