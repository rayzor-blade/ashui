package ashui.canvaskit;

import ashui.draw.DrawContext;
import ashui.draw3d.Material;
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
	?onRotate:Quat->Void,
	?onScale:Vec3->Void,
	?onMove:Vec3->Void
}

/**
	Single object selection for SceneKit (git-bug c16e24c). Register bounds
	inside `draw`, as CanvasKit registers its 2D regions. The application
	keeps its meshes and transforms; the kit reports world rotation deltas.
**/
class Selection3D {
	public final id = Signal.make((null : String));

	final regions = new Map<String, SceneRegion>();
	final materials = new haxe.ds.ObjectMap<Material, {selected:Material, used:Int}>();
	final edges = new SelectionEdges();
	var frame = 0;

	public function new() {}

	/** Selects one registered object, or clears selection with null. **/
	public function select(next:Null<String>):Void
		if (id.get() != next)
			id.set(next);

	public function clear():Void
		select(null);

	public function has(object:String):Bool
		return id.get() == object;

	/** SceneKit starts a registration frame before calling `draw`. **/
	@:allow(ashui.canvaskit.SceneKit)
	function begin(ctx:DrawContext):Void {
		frame++;
		edges.begin(ctx.width);
	}

	@:allow(ashui.canvaskit.SceneKit)
	function end(ctx:DrawContext):Void {
		for (key => r in regions)
			if (r.frame != frame)
				regions.remove(key);
		for (source => entry in materials)
			if (entry.used != frame)
				materials.remove(source);
		if (!edges.empty())
			ctx.drawPass(edges);
		else
			edges.clear();
	}

	/** Release callbacks and bounds when the viewport's owner is disposed. **/
	@:allow(ashui.canvaskit.SceneKit)
	function forgetRegions():Void {
		regions.clear();
		materials.clear();
		edges.dispose();
	}

	/**
		Draws an object's meshes with a subdued selection mask and silhouette edges (8ceba8d, 67cca2c, 8d44ccf).
		Wrap either one `ctx.drawMesh` or a whole model's `draw`. Register its
		bounds with `region` as usual. Materials, textures, shaders and mesh
		vertices are preserved; only the selected object's draws are decorated.
	**/
	public function draw(object:String, ctx:DrawContext, draw:Void->Void):Void {
		var selected = has(object), first = ctx.ops.length;
		draw();
		if (!selected)
			return;
		for (i in first...ctx.ops.length)
			switch ctx.ops[i] {
				case Mesh3D(mesh, at, scene, opacity, material):
					var entry = materials.get(material);
					if (entry == null) {
						entry = {selected: material.with({selected: true}), used: frame};
						materials.set(material, entry);
					}
					entry.used = frame;
					ctx.ops[i] = Mesh3D(mesh, at, scene, opacity, entry.selected);
					// Mesh edges cannot describe texture cutouts or a custom shader's moved vertices.
					// Those still get the mask/rim through the mesh shader's alpha and deformation rules.
					if (material.alphaMode == Opaque && material.shader == null)
						edges.add(mesh, at, opacity);
				case _:
			}
	}

	/**
		Registers local bounds through the same transform used to draw them.
		`onRotate` receives a world rotation delta; compose it before the
		object's rotation. `pivot` is in world coordinates, the transform's
		origin by default. Omit the handler for selection without rotation.
		`onScale` receives positive local X/Y/Z multipliers; multiply them
		into the object's scale. A uniform drag changes all three.
		`onMove` receives world-space translation deltas; add them to its position.
	**/
	public function region(object:String, min:Vec3, max:Vec3, ?transform:Mat4, ?onRotate:Quat->Void, ?pivot:Vec3, ?onScale:Vec3->Void,
			?onMove:Vec3->Void):Void {
		var at = transform != null ? transform : Mat4.IDENTITY;
		var r = regions.get(object);
		if (r == null) {
			regions.set(object, {
				id: object,
				min: min,
				max: max,
				transform: at,
				inverse: at.inverse(),
				pivot: pivot != null ? pivot : at.position(),
				onRotate: onRotate,
				onScale: onScale,
				onMove: onMove,
				frame: frame
			});
		} else {
			var changed = false;
			if (at != r.transform)
				for (i in 0...16)
					if (at.m[i] != r.transform.m[i]) {
						changed = true;
						break;
					}
			if (changed) {
				r.transform = at;
				r.inverse = at.inverse();
			}
			r.min = min;
			r.max = max;
			r.pivot = pivot != null ? pivot : at.position();
			r.onRotate = onRotate;
			r.onScale = onScale;
			r.onMove = onMove;
			r.frame = frame;
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
		var best = far != null ? far : Math.POSITIVE_INFINITY,
			found:Null<String> = null;
		for (r in regions) {
			if (r.inverse == null)
				continue;
			var p = r.inverse.transformPoint(origin),
				d = r.inverse.transformDirection(direction);
			var enter = near, leave = best;
			for (axis in 0...3) {
				var o = axis == 0 ? p.x : axis == 1 ? p.y : p.z;
				var v = axis == 0 ? d.x : axis == 1 ? d.y : d.z;
				var lo = axis == 0 ? r.min.x : axis == 1 ? r.min.y : r.min.z;
				var hi = axis == 0 ? r.max.x : axis == 1 ? r.max.y : r.max.z;
				if (Math.abs(v) < 1e-10) {
					if (o < lo || o > hi) {
						leave = -1;
						break;
					}
				} else {
					var a = (lo - o) / v, b = (hi - o) / v;
					enter = Math.max(enter, Math.min(a, b));
					leave = Math.min(leave, Math.max(a, b));
					if (enter > leave)
						break;
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
