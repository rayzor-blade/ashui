package ashui.layout;

import ashui.layout.PropertyId;
import ashui.layout.IntoReactive;
import ashui.types.Brush;
import ashui.types.Color;
import ashui.types.CornerRadius;

class Node {
	// 64-bit LayoutNodeId minted by Blinc
	public var id(default, null):haxe.Int64;

	public function new(id:haxe.Int64) {
		this.id = id;
	}

	// --- PRIMITIVE DISPATCHERS ---

	public inline function applyF32(prop:PropertyId, reactive:IntoReactive<Single>):Void {
		switch (reactive) {
			case Const(v):
				BlincNative.hl_blinc_apply_f32(this.id, prop, 0, v, null, null);
			case Bound(s):
				BlincNative.hl_blinc_apply_f32(this.id, prop, 1, 0.0, @:privateAccess s.ptr, null);
			case Computed(c):
				BlincNative.hl_blinc_apply_f32(this.id, prop, 2, 0.0, null, @:privateAccess c.ptr);
		}
	}

	public inline function applyI32(prop:PropertyId, reactive:IntoReactive<Int>):Void {
		switch (reactive) {
			case Const(v):
				BlincNative.hl_blinc_apply_i32(this.id, prop, 0, v, null, null);
			case Bound(s):
				BlincNative.hl_blinc_apply_i32(this.id, prop, 1, 0, @:privateAccess s.ptr, null);
			case Computed(c):
				BlincNative.hl_blinc_apply_i32(this.id, prop, 2, 0, null, @:privateAccess c.ptr);
		}
	}

	// --- COMPLEX TYPE DISPATCHERS ---

	public inline function applyBrush(prop:PropertyId, reactive:IntoReactive<Brush>):Void {
		switch (reactive) {
			case Const(v):
				BlincNative.hl_blinc_apply_brush(this.id, prop, 0, @:privateAccess v.ptr, null, null);
			case Bound(s):
				BlincNative.hl_blinc_apply_brush(this.id, prop, 1, null, @:privateAccess s.ptr, null);
			case Computed(c):
				BlincNative.hl_blinc_apply_brush(this.id, prop, 2, null, null, @:privateAccess c.ptr);
		}
	}

	public inline function applyColor(prop:PropertyId, reactive:IntoReactive<Color>):Void {
		switch (reactive) {
			case Const(v):
				BlincNative.hl_blinc_apply_color(this.id, prop, 0, @:privateAccess v.ptr, null, null);
			case Bound(s):
				BlincNative.hl_blinc_apply_color(this.id, prop, 1, null, @:privateAccess s.ptr, null);
			case Computed(c):
				BlincNative.hl_blinc_apply_color(this.id, prop, 2, null, null, @:privateAccess c.ptr);
		}
	}

	public inline function applyCornerRadius(prop:PropertyId, reactive:IntoReactive<CornerRadius>):Void {
		switch (reactive) {
			case Const(v):
				BlincNative.hl_blinc_apply_corner_radius(this.id, prop, 0, @:privateAccess v.ptr, null, null);
			case Bound(s):
				BlincNative.hl_blinc_apply_corner_radius(this.id, prop, 1, null, @:privateAccess s.ptr, null);
			case Computed(c):
				BlincNative.hl_blinc_apply_corner_radius(this.id, prop, 2, null, null, @:privateAccess c.ptr);
		}
	}

	/**
	 * A unified setter that inspects the PropertyId's abstract methods 
	 * and delegates to the correct Rust FFI router automatically.
	 */
	ppublic

	function set<T>(prop:PropertyId, reactive:IntoReactive<T>):Void {
		switch (prop.getDataType()) {
			case TypeF32:
				var r:IntoReactive<Single> = cast reactive;
				switch (r) {
					case Const(v): BlincNative.hl_blinc_apply_f32(this.id, prop, 0, v, null, null);
					case Bound(s): BlincNative.hl_blinc_apply_f32(this.id, prop, 1, 0.0, @:privateAccess s.ptr, null);
					case Computed(c): BlincNative.hl_blinc_apply_f32(this.id, prop, 2, 0.0, null, @:privateAccess c.ptr);
				}

			case TypeI32:
				var r:IntoReactive<Int> = cast reactive;
				switch (r) {
					case Const(v): BlincNative.hl_blinc_apply_i32(this.id, prop, 0, v, null, null);
					case Bound(s): BlincNative.hl_blinc_apply_i32(this.id, prop, 1, 0, @:privateAccess s.ptr, null);
					case Computed(c): BlincNative.hl_blinc_apply_i32(this.id, prop, 2, 0, null, @:privateAccess c.ptr);
				}

			case TypeBrush:
				var r:IntoReactive<Brush> = cast reactive;
				switch (r) {
					case Const(v): BlincNative.hl_blinc_apply_brush(this.id, prop, 0, @:privateAccess v.ptr, null, null);
					case Bound(s): BlincNative.hl_blinc_apply_brush(this.id, prop, 1, null, @:privateAccess s.ptr, null);
					case Computed(c): BlincNative.hl_blinc_apply_brush(this.id, prop, 2, null, null, @:privateAccess c.ptr);
				}

			case TypeColor:
				var r:IntoReactive<Color> = cast reactive;
				switch (r) {
					case Const(v): BlincNative.hl_blinc_apply_color(this.id, prop, 0, @:privateAccess v.ptr, null, null);
					case Bound(s): BlincNative.hl_blinc_apply_color(this.id, prop, 1, null, @:privateAccess s.ptr, null);
					case Computed(c): BlincNative.hl_blinc_apply_color(this.id, prop, 2, null, null, @:privateAccess c.ptr);
				}

			case TypeCornerRadius:
				var r:IntoReactive<CornerRadius> = cast reactive;
				switch (r) {
					case Const(v): BlincNative.hl_blinc_apply_corner_radius(this.id, prop, 0, @:privateAccess v.ptr, null, null);
					case Bound(s): BlincNative.hl_blinc_apply_corner_radius(this.id, prop, 1, null, @:privateAccess s.ptr, null);
					case Computed(c): BlincNative.hl_blinc_apply_corner_radius(this.id, prop, 2, null, null, @:privateAccess c.ptr);
				}

			case TypeTransform:
				var r:IntoReactive<Transform> = cast reactive;
				switch (r) {
					case Const(v): BlincNative.hl_blinc_apply_transform(this.id, prop, 0, @:privateAccess v.ptr, null, null);
					case Bound(s): BlincNative.hl_blinc_apply_transform(this.id, prop, 1, null, @:privateAccess s.ptr, null);
					case Computed(c): BlincNative.hl_blinc_apply_transform(this.id, prop, 2, null, null, @:privateAccess c.ptr);
				}

			case TypeShadow:
				var r:IntoReactive<Shadow> = cast reactive;
				switch (r) {
					case Const(v): BlincNative.hl_blinc_apply_shadow(this.id, prop, 0, @:privateAccess v.ptr, null, null);
					case Bound(s): BlincNative.hl_blinc_apply_shadow(this.id, prop, 1, null, @:privateAccess s.ptr, null);
					case Computed(c): BlincNative.hl_blinc_apply_shadow(this.id, prop, 2, null, null, @:privateAccess c.ptr);
				}

			case TypeString:
				var r:IntoReactive<String> = cast reactive;
				switch (r) {
					case Const(v):
						// v.bytes safely extracts the underlying UTF-8 hl.Bytes buffer
						var bytes = v != null ? v.bytes : null;
						BlincNative.hl_blinc_apply_string(this.id, prop, 0, bytes, null, null);
					case Bound(s):
						BlincNative.hl_blinc_apply_string(this.id, prop, 1, null, @:privateAccess s.ptr, null);
					case Computed(c):
						BlincNative.hl_blinc_apply_string(this.id, prop, 2, null, null, @:privateAccess c.ptr);
				}
		}
	}
}
