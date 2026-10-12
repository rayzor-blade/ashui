package ashui.canvaskit;

import ashui.math.Mat4;
import ashui.math.Quat;
import ashui.math.Vec3;
import ashui.reactive.Signal;

/** A selectable object's local bounds, placement and optional world rotation handler. **/
typedef SceneRegion = {
	id:String,
	min:Vec3,
	max:Vec3,
	transform:Mat4,
	inverse:Null<Mat4>,
	pivot:Vec3,
	frame:Int,
	?onRotate:Quat->Void
}

/**
	Single object selection for SceneKit (git-bug c16e24c). Register bounds
	inside `draw`, as CanvasKit registers its 2D regions. The application
	keeps its meshes and transforms; the kit reports world rotation deltas.
**/
class Selection3D {
	public final id = Signal.make((null : String));
	final regions = new Map<String, SceneRegion>();
	var frame = 0;

	public function new() {}

	/** Selects one registered object, or clears selection with null. **/
	public function select(next:Null<String>):Void
		if (id.get() != next) id.set(next);

	public function clear():Void
		select(null);

	public function has(object:String):Bool
		return id.get() == object;

	/** SceneKit clears last frame's regions before calling `draw`. **/
	@:allow(ashui.canvaskit.SceneKit)
	function begin():Void
		frame++;

	@:allow(ashui.canvaskit.SceneKit)
	function end():Void
		for (key => r in regions) if (r.frame != frame) regions.remove(key);

	/** Release callbacks and bounds when the viewport's owner is disposed. **/
	@:allow(ashui.canvaskit.SceneKit)
	function forgetRegions():Void
		regions.clear();

	/**
		Registers local bounds through the same transform used to draw them.
		`onRotate` receives a world rotation delta; compose it before the
		object's rotation. `pivot` is in world coordinates, the transform's
		origin by default. Omit the handler for selection without rotation.
	**/
	public function region(object:String, min:Vec3, max:Vec3, ?transform:Mat4, ?onRotate:Quat->Void, ?pivot:Vec3):Void {
		var at = transform != null ? transform : Mat4.IDENTITY;
		var r = regions.get(object);
		if (r == null) {
			regions.set(object, {id: object, min: min, max: max, transform: at, inverse: at.inverse(),
				pivot: pivot != null ? pivot : at.position(), onRotate: onRotate, frame: frame});
		} else {
			var changed = false;
			if (at != r.transform) for (i in 0...16) if (at.m[i] != r.transform.m[i]) { changed = true; break; }
			if (changed) { r.transform = at; r.inverse = at.inverse(); }
			r.min = min; r.max = max; r.pivot = pivot != null ? pivot : at.position(); r.onRotate = onRotate; r.frame = frame;
		}
	}

	public function get(object:String):Null<SceneRegion>
		return regions.get(object);

	public function selected():Null<SceneRegion> {
		var object = id.get();
		return object == null ? null : get(object);
	}

	/** Nearest oriented bounding box along a world ray; singular transforms cannot be picked. **/
	public function pick(origin:Vec3, direction:Vec3, near = 0.0, ?far:Float):Null<String> {
		var best = far != null ? far : Math.POSITIVE_INFINITY, found:Null<String> = null;
		for (r in regions) {
			if (r.inverse == null) continue;
			var p = r.inverse.transformPoint(origin), d = r.inverse.transformDirection(direction);
			var enter = near, leave = best;
			for (axis in 0...3) {
				var o = axis == 0 ? p.x : axis == 1 ? p.y : p.z;
				var v = axis == 0 ? d.x : axis == 1 ? d.y : d.z;
				var lo = axis == 0 ? r.min.x : axis == 1 ? r.min.y : r.min.z;
				var hi = axis == 0 ? r.max.x : axis == 1 ? r.max.y : r.max.z;
				if (Math.abs(v) < 1e-10) {
					if (o < lo || o > hi) { leave = -1; break; }
				} else {
					var a = (lo - o) / v, b = (hi - o) / v;
					enter = Math.max(enter, Math.min(a, b));
					leave = Math.min(leave, Math.max(a, b));
					if (enter > leave) break;
				}
			}
			if (enter <= leave && (enter < best || (enter == best && (found == null || r.id < found)))) {
				best = enter;
				found = r.id;
			}
		}
		return found;
	}
}
