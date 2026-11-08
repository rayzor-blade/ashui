package ashui.core.externs;

#if ashui_rayzor
/** A layout tree of the `blinc_abi` Rayzor plugin; free it with `blinc_tree_release`. **/
@:native("ashui::blinc::Tree")
extern class BlincTree {}

/** A signal of the plugin's reactive graph; free it with `blinc_signal_release`. **/
@:native("ashui::blinc::Signal")
extern class BlincSignal {}

/** A style value (brush, colour, radius, shadow, transform, clip path); free it with `blinc_value_release`. **/
@:native("ashui::blinc::StyleValue")
extern class BlincValue {}

/** A computed of the reactive graph. The plugin has none yet: computeds need a callback into Haxe. **/
@:native("ashui::blinc::Computed")
extern class BlincComputed {}

/** A CSS engine; free it with `blinc_css_release`. **/
@:native("ashui::blinc::Css")
extern class BlincCss {}

/** A parsed stylesheet; free it with `blinc_sheet_release`. **/
@:native("ashui::blinc::Sheet")
extern class BlincSheet {}

/**
	The `blinc_abi` Rayzor plugin, one function per export. The wrappers in `BlincNative`, `LayoutTreeNative`
	and the other `*Native` classes give these the shape the rest of ashui calls; ashui code does not use this class.
	Every handle is freed by hand: Rayzor drops nothing a plugin allocates.
**/
@:native("ashui::blinc::BlincNative")
extern class BlincPlugin {
	public static function blinc_tree_new():BlincTree;
	public static function blinc_tree_create_node(self_:BlincTree):haxe.Int64;
	public static function blinc_tree_add_child(self_:BlincTree, parent:haxe.Int64, child:haxe.Int64):Void;
	public static function blinc_tree_remove_node(self_:BlincTree, node:haxe.Int64):Void;
	public static function blinc_tree_remove_subtree(self_:BlincTree, node:haxe.Int64):Void;
	public static function blinc_tree_clear_children(self_:BlincTree, parent:haxe.Int64):Void;
	public static function blinc_tree_compute_layout(self_:BlincTree, root:haxe.Int64, width:Float, height:Float):Void;
	public static function blinc_tree_get_bounds(self_:BlincTree, node:haxe.Int64, out:haxe.io.Bytes):Bool;
	public static function blinc_tree_create_text_node(self_:BlincTree, content:String, font_name:String, font_size:Float, line_height:Float, font_weight:Int, generic_font:Int, flags:Int):haxe.Int64;
	public static function blinc_tree_replace_node(self_:BlincTree, old:haxe.Int64, next:haxe.Int64):Void;
	public static function blinc_tree_replace_children(self_:BlincTree, parent:haxe.Int64, children:haxe.io.Bytes):Void;
	public static function blinc_tree_set_children(self_:BlincTree, parent:haxe.Int64, children:haxe.io.Bytes):Void;
	public static function blinc_tree_set_grid_rows(self_:BlincTree, group:haxe.Int64, rows:haxe.io.Bytes):Bool;
	public static function blinc_tree_children(self_:BlincTree, node:haxe.Int64, out:haxe.io.Bytes):Int;
	public static function blinc_tree_ancestors(self_:BlincTree, node:haxe.Int64, out:haxe.io.Bytes):Int;
	public static function blinc_tree_get_box(self_:BlincTree, node:haxe.Int64, out:haxe.io.Bytes):Bool;
	public static function blinc_tree_box_edges(self_:BlincTree, node:haxe.Int64, out:haxe.io.Bytes):Bool;
	public static function blinc_tree_in_view(self_:BlincTree, node:haxe.Int64):Bool;
	public static function blinc_tree_text_align(self_:BlincTree, node:haxe.Int64):Int;
	public static function blinc_tree_text_limits(self_:BlincTree, node:haxe.Int64, out:haxe.io.Bytes):Void;
	public static function blinc_tree_display_list(self_:BlincTree, root:haxe.Int64, params:haxe.io.Bytes, out:haxe.io.Bytes):Int;
	public static function blinc_tree_set_image(self_:BlincTree, node:haxe.Int64, slot:Int):Void;
	public static function blinc_tree_set_image_mapping(self_:BlincTree, node:haxe.Int64, fit:Int, x:Float, y:Float, offset_x:Float, offset_y:Float):Void;
	public static function blinc_tree_set_canvas(self_:BlincTree, node:haxe.Int64, slot:Int):Void;
	public static function blinc_tree_set_notch(self_:BlincTree, node:haxe.Int64, data:haxe.io.Bytes):Void;
	public static function blinc_tree_set_visual(self_:BlincTree, node:haxe.Int64, dx:Float, dy:Float, w:Float, h:Float, clear:Bool):Void;
	public static function blinc_tree_set_pass_through(self_:BlincTree, node:haxe.Int64, through:Bool):Void;
	public static function blinc_tree_set_scrollbar_style(self_:BlincTree, node:haxe.Int64, width:Float, track:Int):Void;
	public static function blinc_tree_set_scroll(self_:BlincTree, node:haxe.Int64, x:Float, y:Float, thumb:Int):Void;
	public static function blinc_tree_scroll_extent(self_:BlincTree, node:haxe.Int64, out:haxe.io.Bytes):Bool;
	public static function blinc_tree_hit_test(self_:BlincTree, root:haxe.Int64, x:Float, y:Float, out:haxe.io.Bytes):Int;
	public static function blinc_tree_hit_test_region(self_:BlincTree, root:haxe.Int64, x:Float, y:Float, out:haxe.io.Bytes, bounds:haxe.io.Bytes):Int;
	public static function blinc_tree_order(self_:BlincTree, root:haxe.Int64, out:haxe.io.Bytes):Int;
	public static function blinc_tree_path(self_:BlincTree, root:haxe.Int64, node:haxe.Int64, out:haxe.io.Bytes):Int;
	public static function blinc_text_carets(self_:BlincTree, node:haxe.Int64, text:String, font_size:Float, wrap_width:Float, out:haxe.io.Bytes, info:haxe.io.Bytes):Int;
	public static function blinc_tree_apply_f32(self_:BlincTree, node:haxe.Int64, prop:Int, value:Float):Void;
	public static function blinc_tree_apply_i32(self_:BlincTree, node:haxe.Int64, prop:Int, value:Int):Void;
	public static function blinc_tree_apply_string(self_:BlincTree, node:haxe.Int64, prop:Int, value:String):Void;
	public static function blinc_tree_apply_value(self_:BlincTree, node:haxe.Int64, prop:Int, value:BlincValue):Void;
	public static function blinc_tree_bind_f32(self_:BlincTree, node:haxe.Int64, prop:Int, signal:BlincSignal):Void;
	public static function blinc_tree_bind_i32(self_:BlincTree, node:haxe.Int64, prop:Int, signal:BlincSignal):Void;
	public static function blinc_tree_bind_string(self_:BlincTree, node:haxe.Int64, prop:Int, signal:BlincSignal):Void;
	public static function blinc_tree_bind_value(self_:BlincTree, node:haxe.Int64, prop:Int, signal:BlincSignal):Void;
	public static function blinc_tree_unset(self_:BlincTree, node:haxe.Int64, prop:Int):Void;
	public static function blinc_tree_flush(self_:BlincTree):Bool;
	public static function blinc_tree_dispose(self_:BlincTree):Void;
	public static function blinc_tree_release(h:BlincTree):Void;
	public static function blinc_css_new():BlincCss;
	public static function blinc_css_add(self_:BlincCss, source:String, file:String, at:Int):Int;
	public static function blinc_css_diagnostics(self_:BlincCss):String;
	public static function blinc_css_add_parsed(self_:BlincCss, sheet:BlincSheet, at:Int):Int;
	public static function blinc_css_add_compiled(self_:BlincCss, bytes:haxe.io.Bytes, at:Int):Int;
	public static function blinc_css_remove(self_:BlincCss, id:Int):Int;
	public static function blinc_css_keyframes(self_:BlincCss, name:String):String;
	public static function blinc_css_root_variable(self_:BlincCss, name:String):String;
	public static function blinc_css_set_theme(self_:BlincCss, vars:String):Void;
	public static function blinc_css_set_environment(self_:BlincCss, width:Float, height:Float, dark:Bool, root_font_size:Float):Void;
	public static function blinc_css_set_element(self_:BlincCss, node:haxe.Int64, desc:String):Void;
	public static function blinc_css_state_bit(name:String):Int;
	public static function blinc_css_set_states(self_:BlincCss, node:haxe.Int64, mask:Int):Void;
	public static function blinc_css_moved(self_:BlincCss, node:haxe.Int64):Void;
	public static function blinc_css_children_changed(self_:BlincCss, parent:haxe.Int64):Void;
	public static function blinc_css_forget(self_:BlincCss, node:haxe.Int64):Void;
	public static function blinc_css_restyle(self_:BlincCss, tree:BlincTree, root:haxe.Int64):Int;
	public static function blinc_css_update_containers(self_:BlincCss, tree:BlincTree):Int;
	public static function blinc_css_update_containers_under(self_:BlincCss, tree:BlincTree, root:haxe.Int64):Int;
	public static function blinc_css_take_changed(self_:BlincCss, out:haxe.io.Bytes):Int;
	public static function blinc_css_take_watched(self_:BlincCss, nodes:haxe.io.Bytes, bits:haxe.io.Bytes):Int;
	public static function blinc_css_select(self_:BlincCss, tree:BlincTree, root:haxe.Int64, selectors:String, out:haxe.io.Bytes):Int;
	public static function blinc_css_explain(self_:BlincCss, tree:BlincTree, node:haxe.Int64):String;
	public static function blinc_css_style(self_:BlincCss, node:haxe.Int64):String;
	public static function blinc_css_release(h:BlincCss):Void;
	public static function blinc_sheet_parse(source:String, file:String):BlincSheet;
	public static function blinc_sheet_decode(bytes:haxe.io.Bytes):BlincSheet;
	public static function blinc_sheet_diagnostics(self_:BlincSheet):String;
	public static function blinc_sheet_imports(self_:BlincSheet):String;
	public static function blinc_sheet_declared(self_:BlincSheet):String;
	public static function blinc_sheet_release(h:BlincSheet):Void;
	public static function blinc_res_decode_bitmap(bytes:haxe.io.Bytes):Int;
	public static function blinc_res_bitmap_size(slot:Int, height:Bool):Int;
	public static function blinc_res_release_bitmap(slot:Int):Void;
	public static function blinc_res_resample_bitmap(slot:Int, width:Int, height:Int, fit:Int, out:haxe.io.Bytes):Bool;
	public static function blinc_res_shrink_bitmap(slot:Int, max_side:Int):Bool;
	public static function blinc_res_rasterize_svg(markup:String, width:Int, height:Int, out:haxe.io.Bytes):Bool;
	public static function blinc_res_text_atlas(color:Int, seen:Int, out:haxe.io.Bytes, info:haxe.io.Bytes):Int;
	public static function blinc_res_text_outline(text:String, font_name:String, style:haxe.io.Bytes, out:haxe.io.Bytes, info:haxe.io.Bytes):Int;
	public static function blinc_res_register_font(bytes:haxe.io.Bytes):Int;

	// --- Reactive: signals, host effects ---
	public static function blinc_is_dirty():Bool;
	public static function blinc_clear_dirty():Void;
	public static function blinc_signal_i32(initial:Int):BlincSignal;
	public static function blinc_signal_get_i32(sig:BlincSignal):Int;
	public static function blinc_signal_set_i32(sig:BlincSignal, v:Int):Void;
	public static function blinc_signal_f32(initial:Float):BlincSignal;
	public static function blinc_signal_get_f32(sig:BlincSignal):Float;
	public static function blinc_signal_set_f32(sig:BlincSignal, v:Float):Void;
	public static function blinc_signal_f64(initial:Float):BlincSignal;
	public static function blinc_signal_get_f64(sig:BlincSignal):Float;
	public static function blinc_signal_set_f64(sig:BlincSignal, v:Float):Void;
	public static function blinc_signal_bool(initial:Bool):BlincSignal;
	public static function blinc_signal_get_bool(sig:BlincSignal):Bool;
	public static function blinc_signal_set_bool(sig:BlincSignal, v:Bool):Void;
	public static function blinc_signal_string(initial:String):BlincSignal;
	public static function blinc_signal_get_string(sig:BlincSignal):String;
	public static function blinc_signal_set_string(sig:BlincSignal, v:String):Void;
	public static function blinc_signal_string_version(sig:BlincSignal):Int;
	public static function blinc_signal_touch(sig:BlincSignal):Void;
	public static function blinc_signal_release(sig:BlincSignal):Void;
	public static function blinc_host_effect_new():Int;
	public static function blinc_host_effects_due(out:haxe.io.Bytes, capacity:Int):Int;
	public static function blinc_host_effect_begin(slot:Int):Bool;
	public static function blinc_host_effect_end(slot:Int):Void;
	public static function blinc_host_effect_release(slot:Int):Void;

	// --- Style values ---
	public static function blinc_value_release(h:BlincValue):Void;
	public static function blinc_signal_value(initial:BlincValue):BlincSignal;
	public static function blinc_signal_set_value(sig:BlincSignal, v:BlincValue):Void;
	public static function blinc_brush_solid(hex:Int, alpha:Float):BlincValue;
	public static function blinc_brush_glass(blur:Float, tint_hex:Int, tint_alpha:Float, simple:Int, noise:Float):BlincValue;
	public static function blinc_brush_glass_aberration(brush:BlincValue, strength:Float):Void;
	public static function blinc_brush_glass_bevel(brush:BlincValue, strength:Float, inset:Bool):Void;
	public static function blinc_brush_blur(radius:Float, tint_hex:Int, tint_alpha:Float):BlincValue;
	public static function blinc_brush_image(src:String, fit:Int):BlincValue;
	public static function blinc_brush_image_mapping(brush:BlincValue, x:Float, y:Float, offset_x:Float, offset_y:Float, repeat:Int):Void;
	public static function blinc_brush_linear_gradient(sx:Float, sy:Float, ex:Float, ey:Float, from_hex:Int, from_alpha:Float, to_hex:Int, to_alpha:Float):BlincValue;
	public static function blinc_brush_gradient(radial:Bool, x1:Float, y1:Float, x2:Float, y2:Float, bbox:Bool):BlincValue;
	public static function blinc_brush_gradient_stop(brush:BlincValue, offset:Float, hex:Int, alpha:Float):Void;
	public static function blinc_color_hex(hex:Int, alpha:Float):BlincValue;
	public static function blinc_corner_radius(tl:Float, tr:Float, br:Float, bl:Float):BlincValue;
	public static function blinc_corner_shape(top_left:Float, top_right:Float, bottom_right:Float, bottom_left:Float, locked:Bool):BlincValue;
	public static function blinc_transform_identity():BlincValue;
	public static function blinc_transform_translate(x:Float, y:Float):BlincValue;
	public static function blinc_transform_affine(a:Float, b:Float, c:Float, d:Float, tx:Float, ty:Float):BlincValue;
	public static function blinc_shadow(offset_x:Float, offset_y:Float, blur:Float, spread:Float, hex:Int, alpha:Float, inset:Bool):BlincValue;
	public static function blinc_shadow_push(shadow:BlincValue, offset_x:Float, offset_y:Float, blur:Float, spread:Float, hex:Int, alpha:Float, inset:Bool):Void;
	public static function blinc_clip_path(kind:Int, values:haxe.io.Bytes, percent:Int, none:Int, round:Float):BlincValue;
	public static function blinc_clip_polygon(values:haxe.io.Bytes, percent:haxe.io.Bytes, count:Int, path:Bool):BlincValue;
	public static function blinc_clip_even_odd(clip:BlincValue):BlincValue;
	public static function blinc_text_decoration(lines:Int, style:Int, hex:Int, alpha:Float, thickness:Float, offset:Float):BlincValue;
}
#end
