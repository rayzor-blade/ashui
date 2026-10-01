package ashui.core;

import ashui.layout.PropertyId;
import ashui.layout.IntoReactive;
import ashui.types.Brush;
import ashui.types.Color;
import ashui.types.CornerRadius;

class BlincNode {
    // 64-bit LayoutNodeId minted by Blinc
    public var id(default, null): haxe.Int64;

    public function new(id: haxe.Int64) {
        this.id = id;
    }

    // --- PRIMITIVE DISPATCHERS ---

    public inline function applyF32(prop: PropertyId, reactive: IntoReactive<Single>): Void {
        switch (reactive) {
            case Const(v):
                BlincNative.hl_blinc_apply_f32(this.id, prop, 0, v, null, null);
            case Bound(s):
                BlincNative.hl_blinc_apply_f32(this.id, prop, 1, 0.0, @:privateAccess s.ptr, null);
            case Computed(c):
                BlincNative.hl_blinc_apply_f32(this.id, prop, 2, 0.0, null, @:privateAccess c.ptr);
        }
    }

    public inline function applyI32(prop: PropertyId, reactive: IntoReactive<Int>): Void {
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

    public inline function applyBrush(prop: PropertyId, reactive: IntoReactive<Brush>): Void {
        switch (reactive) {
            case Const(v):
                BlincNative.hl_blinc_apply_brush(this.id, prop, 0, @:privateAccess v.ptr, null, null);
            case Bound(s):
                BlincNative.hl_blinc_apply_brush(this.id, prop, 1, null, @:privateAccess s.ptr, null);
            case Computed(c):
                BlincNative.hl_blinc_apply_brush(this.id, prop, 2, null, null, @:privateAccess c.ptr);
        }
    }

    public inline function applyColor(prop: PropertyId, reactive: IntoReactive<Color>): Void {
        switch (reactive) {
            case Const(v):
                BlincNative.hl_blinc_apply_color(this.id, prop, 0, @:privateAccess v.ptr, null, null);
            case Bound(s):
                BlincNative.hl_blinc_apply_color(this.id, prop, 1, null, @:privateAccess s.ptr, null);
            case Computed(c):
                BlincNative.hl_blinc_apply_color(this.id, prop, 2, null, null, @:privateAccess c.ptr);
        }
    }

    public inline function applyCornerRadius(prop: PropertyId, reactive: IntoReactive<CornerRadius>): Void {
        switch (reactive) {
            case Const(v):
                BlincNative.hl_blinc_apply_corner_radius(this.id, prop, 0, @:privateAccess v.ptr, null, null);
            case Bound(s):
                BlincNative.hl_blinc_apply_corner_radius(this.id, prop, 1, null, @:privateAccess s.ptr, null);
            case Computed(c):
                BlincNative.hl_blinc_apply_corner_radius(this.id, prop, 2, null, null, @:privateAccess c.ptr);
        }
    }
}