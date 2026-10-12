package ashui.canvaskit;

import ashui.canvaskit.Selection3D.SceneRegion;
import ashui.draw.DrawContext;
import ashui.draw.Affine;
import ashui.draw.Path;
import ashui.draw.Stroke;
import ashui.draw3d.Camera;
import ashui.input.Interaction;
import ashui.input.Pointer;
import ashui.layout.LayoutTree;
import ashui.math.Quat;
import ashui.math.Mat4;
import ashui.math.Vec3;
import ashui.reactive.Owner;
import ashui.state.Machine;
import ashui.types.Brush;

private typedef Point = {x:Float, y:Float};
private typedef Segment = {a:Point, b:Point, handle:Int, front:Bool, vector:Vec3};
private typedef Arm = {x:Float, y:Float, depth:Float, handle:Int};
private typedef RingBounds = {left:Float, top:Float, right:Float, bottom:Float};
private typedef Drag = {
	region:SceneRegion, axis:Vec3, pivot:Vec3, camera:Camera, width:Float, height:Float,
	center:Point, last:Point, vector:Null<Vec3>, angle:Float, total:Float,
	map:Affine, rotate:Quat->Void
};

private enum Phase { Idle; Hover(handle:Int); Rotating(handle:Int); }
private enum Action { PointAt(handle:Int); Grab(handle:Int); Finish; }

/**
	SceneKit's rotation rings and world orientation widget (c16e24c).
	Paths are projected once when the reactive canvas records a changed
	scene, then reused for picking. Only a captured drag installs a pointer
	hook; there is no timer or frame loop while idle.
**/
class SceneGizmos {
	static final axes = [new Vec3(1, 0, 0), Vec3.UP, new Vec3(0, 0, 1)];
	static final colors = [0xf16c78, 0x8bd45c, 0x6aa9ff];
	static final brushes = [for (color in colors) Brush.solid(color)];
	static final white = Brush.solid(0xffffff);
	static final dark = Brush.solid(0x111827, 0.8);
	static final worldBackground = Brush.solid(0x111827, 0.32);
	static final names = ["X", "Y", "Z"];
	static final labelStyle:ashui.draw.GlyphOutlines.TextStyle = {size: 11, align: Middle, baseline: Middle};
	static final thin = new Stroke(2.2, Round, Round);
	static final thick = new Stroke(3.4, Round, Round);
	static final halo = new Stroke(4.8, Round, Round);
	static inline var STEPS = 96;
	// Shared unit circles, rather than evaluating trigonometry on every pointer event.
	static final circles = [for (axis in 0...3) [for (i in 0...STEPS + 1) {
		var t = i * Math.PI * 2 / STEPS, c = Math.cos(t), s = Math.sin(t);
		axis == 0 ? new Vec3(0, c, s) : axis == 1 ? new Vec3(s, 0, c) : new Vec3(c, s, 0);
	}]];

	public final camera:OrbitCamera;
	public final selection:Null<Selection3D>;
	public var world = false;
	/** False when SceneKit's camera controls are disabled; the world widget remains visible. **/
	public var cameraControls = true;
	public var worldRight = 16.0;
	public var worldTop = 16.0;
	/** The selected rings' minimum and maximum screen radius, in layout units. **/
	public var minRadius = 72.0;
	public var maxRadius = 180.0;

	final phase = new Machine<Phase, Action>(Idle, (state, event) -> switch [state, event] {
		case [Rotating(_), PointAt(_)]: null;
		case [_, PointAt(handle)]: handle < 0 ? Idle : Hover(handle);
		case [_, Grab(handle)]: Rotating(handle);
		case [_, Finish]: Idle;
	});
	var segments:Array<Segment> = [];
	var ringBounds:Null<RingBounds>;
	var arms:Array<Arm> = [];
	var worldCenter:Point = {x: 0, y: 0};
	var width = 0.0;
	var height = 0.0;
	var viewed:Null<Camera>;
	var view:Mat4 = Mat4.IDENTITY;
	var focal = 0.0;
	var drag:Null<Drag>;
	var hook:Null<LayoutTree->Void>;
	var suppressClick = false;
	var down:Point = {x: 0, y: 0};

	public function new(camera:OrbitCamera, ?selection:Selection3D) {
		this.camera = camera;
		this.selection = selection;
	}

	/** Draw after the meshes: clear editor lines above the lit/post-processed image. **/
	public function draw(ctx:DrawContext):Void {
		width = ctx.width; height = ctx.height; viewed = ctx.currentScene().camera;
		view = viewed.view(); focal = height / (2 * Math.tan(viewed.fovY / 2));
		segments = []; arms = []; ringBounds = null;
		var active = switch phase.state.get() { case Hover(h), Rotating(h): h; case Idle: -1; };
		ctx.pushClipRect(0, 0, width, height);
		var selected = selection != null ? selection.selected() : null;
		if (selected != null && selected.onRotate != null) drawRings(ctx, selected, active);
		if (world) drawWorld(ctx, active);
		ctx.popClip();
	}

	function drawRings(ctx:DrawContext, r:SceneRegion, active:Int):Void {
		var center = projectPoint(r.pivot);
		if (center == null) return;
		var forward = viewed.target.sub(viewed.eye).normalize();
		var depth = r.pivot.sub(viewed.eye).dot(forward);
		var extent = 0.0;
		for (x in [r.min.x, r.max.x]) for (y in [r.min.y, r.max.y]) for (z in [r.min.z, r.max.z]) {
			var corner = r.transform.transformPoint(new Vec3(x, y, z));
			extent = Math.max(extent, corner.distance(r.pivot));
		}
		// A bounding sphere keeps the rings stable as the selected object rotates.
		var radius = Math.min(maxRadius, Math.max(minRadius, extent * focal / depth * 1.12));
		var size = radius * 2 * depth * Math.tan(viewed.fovY / 2) / height;
		var fronts:Array<Path> = [], backs:Array<Path> = [];
		for (axis in 0...3) {
			var front = new Path(), back = new Path();
			var previous:Null<Bool> = null;
			for (i in 0...STEPS) {
				var a = circles[axis][i], b = circles[axis][i + 1];
				var pa = projectPoint(r.pivot.add(a.scale(size)));
				var pb = projectPoint(r.pivot.add(b.scale(size)));
				if (pa == null || pb == null) continue;
				var near = a.add(b).dot(viewed.eye.sub(r.pivot)) >= 0;
				var path = near ? front : back;
				if (previous == null || previous != near) path.moveTo(pa.x, pa.y);
				path.lineTo(pb.x, pb.y); previous = near;
				segments.push({a: pa, b: pb, handle: axis, front: near, vector: a});
			}
			fronts.push(front); backs.push(back);
		}
		// Back halves remain visible through the object but quieter; front halves paint last.
		for (axis in 0...3) {
			ctx.pushOpacity(active == axis ? 0.65 : 0.28);
			ctx.strokePath(backs[axis], active == axis ? thick : thin, brushes[axis]);
			ctx.popOpacity();
		}
		for (axis in 0...3) {
			ctx.strokePath(fronts[axis], halo, dark);
			ctx.strokePath(fronts[axis], active == axis ? thick : thin, active == axis ? white : brushes[axis]);
		}
		// The outside circle rotates in the view plane, as in an editor's trackball.
		var outer = radius * 1.18;
		ctx.pushOpacity(active == 3 ? 1 : 0.55);
		ctx.strokeCircle(center.x, center.y, outer, active == 3 ? thick : thin, white);
		ctx.popOpacity();
		for (i in 0...STEPS) {
			var a = circles[2][i], b = circles[2][i + 1];
			segments.push({a: {x: center.x + a.x * outer, y: center.y - a.y * outer},
				b: {x: center.x + b.x * outer, y: center.y - b.y * outer}, handle: 3, front: true, vector: a});
		}
		ringBounds = {left: center.x - outer - 7, top: center.y - outer - 7, right: center.x + outer + 7, bottom: center.y + outer + 7};
		for (s in segments) {
			ringBounds.left = Math.min(ringBounds.left, s.a.x - 7); ringBounds.top = Math.min(ringBounds.top, s.a.y - 7);
			ringBounds.right = Math.max(ringBounds.right, s.a.x + 7); ringBounds.bottom = Math.max(ringBounds.bottom, s.a.y + 7);
		}
	}

	function drawWorld(ctx:DrawContext, active:Int):Void {
		if (width < 112 || height < 112) return;
		worldCenter = {x: width - worldRight - 48, y: worldTop + 48};
		for (axis in 0...3) for (sign in [-1, 1]) {
			var v = view.transformDirection(axes[axis].scale(sign));
			arms.push({x: worldCenter.x + v.x * 31, y: worldCenter.y - v.y * 31, depth: v.z,
				handle: 4 + axis * 2 + (sign > 0 ? 1 : 0)});
		}
		arms.sort((a, b) -> a.depth < b.depth ? -1 : a.depth > b.depth ? 1 : a.handle - b.handle);
		ctx.fillCircle(worldCenter.x, worldCenter.y, 46, worldBackground);
		for (arm in arms) {
			var axis = Std.int((arm.handle - 4) / 2), positive = (arm.handle & 1) == 1;
			var dx = arm.x - worldCenter.x, dy = arm.y - worldCenter.y;
			var length = Math.sqrt(dx * dx + dy * dy);
			var color = active == arm.handle ? white : brushes[axis];
			ctx.pushOpacity(positive ? 1 : 0.45);
			ctx.line(worldCenter.x, worldCenter.y, arm.x, arm.y, thin, color);
			if (positive && length > 3) {
				var ux = dx / length, uy = dy / length;
				ctx.fillPath(new Path().moveTo(arm.x, arm.y).lineTo(arm.x - ux * 11 - uy * 5, arm.y - uy * 11 + ux * 5)
					.lineTo(arm.x - ux * 11 + uy * 5, arm.y - uy * 11 - ux * 5).close(), color);
			} else ctx.fillCircle(arm.x, arm.y, positive ? 6 : 4, color);
			ctx.popOpacity();
			if (positive) {
				var along = length > 3 ? 9 / length : 0;
				ctx.text(names[axis], arm.x + dx * along, arm.y + dy * along, white, labelStyle);
			}
		}
		ctx.fillCircle(worldCenter.x, worldCenter.y, 4, white);
	}

	/** The last recorded handle under a canvas-local point; -1 for empty space. **/
	public function hit(x:Float, y:Float):Int {
		if (x < 0 || y < 0 || x > width || y > height) return -1;
		var nearest = 10.0, handle = -1;
		// Front arms win where an axis points into the view and several overlap.
		var overWorld = Math.abs(x - worldCenter.x) < 42 && Math.abs(y - worldCenter.y) < 42;
		var i = cameraControls && overWorld ? arms.length : 0;
		while (i-- > 0) {
			var a = arms[i], dx = a.x - x, dy = a.y - y, d = Math.sqrt(dx * dx + dy * dy);
			if (d < nearest) { nearest = d; handle = a.handle; }
		}
		if (handle >= 0) return handle;
		if (ringBounds == null || x < ringBounds.left || y < ringBounds.top || x > ringBounds.right || y > ringBounds.bottom) return -1;
		nearest = 7;
		for (s in segments) {
			var d = lineDistance(x, y, s.a, s.b);
			if (d < nearest - 0.01 || (Math.abs(d - nearest) < 0.01 && s.front)) {
				nearest = d; handle = s.handle;
			}
		}
		return handle;
	}

	/** Editor controls precede OrbitInput; handled presses prevent a camera drag. **/
	public function attach(node:ashui.layout.Node):Void {
		var input = Interaction.of(node).setFocusable(true);
		input.onPointerMove(p -> if (drag == null) hover(hit(p.localX, p.localY)));
		input.onPointerLeave(_ -> if (drag == null) hover(-1));
		input.onPointerDown(p -> {
			suppressClick = false;
			down = {x: p.localX, y: p.localY};
			if (p.button != Left || p.shift || viewed == null) return;
			var handle = hit(p.localX, p.localY);
			if (handle >= 4) {
				suppressClick = true;
				snapView(handle);
				p.preventDefault();
				return;
			}
			var r = selection != null ? selection.selected() : null;
			if (handle < 0 || r == null || r.onRotate == null) return;
			var center = projectPoint(r.pivot);
			if (center == null) return;
			var axis = handle == 3 ? viewed.eye.sub(viewed.target).normalize() : axes[handle];
			var vector = planeVector(viewed, p.localX, p.localY, width, height, r.pivot, axis);
			if (vector == null || Math.abs(axis.dot(viewed.eye.sub(viewed.target).normalize())) < 0.15) {
				var nearest = Math.POSITIVE_INFINITY;
				for (s in segments) if (s.handle == handle) {
					var distance = lineDistance(p.localX, p.localY, s.a, s.b);
					if (distance < nearest) { nearest = distance; vector = s.vector; }
				}
			}
			drag = {region: r, axis: axis, pivot: r.pivot, camera: viewed, width: width, height: height, center: center,
				last: down, vector: vector,
				angle: Math.atan2(center.y - p.localY, p.localX - center.x), total: 0,
				map: pointerMap(node, p.x, p.y, p.localX, p.localY), rotate: r.onRotate};
			phase.send(Grab(handle));
			suppressClick = true;
			p.preventDefault();
			var tree = node.tree;
			hook = t -> if (t == tree && drag != null) {
				var at = Pointer.at(tree);
				if (!at.pressed || !at.inside || selection == null || selection.id.get() != drag.region.id) {
					finish(!at.inside || selection == null || selection.id.get() != drag.region.id);
					return;
				}
				move(drag.map.x(at.x, at.y), drag.map.y(at.x, at.y));
			};
			Pointer.hooks.push(hook);
		});
		input.onClick(p -> {
			if (suppressClick || selection == null || viewed == null || distance(down, {x: p.localX, y: p.localY}) > 3) return;
			var ray = ray(viewed, p.localX, p.localY, width, height);
			selection.select(selection.pick(ray.origin, ray.direction, viewed.near, viewed.far));
		});
		input.onWheel(p -> if (drag != null) p.preventDefault());
		input.onKeyDown(p -> if (p.key.match(Named(Escape)) && drag != null) { finish(true); p.preventDefault(); });
		input.onBlur(_ -> if (drag != null) finish(true));
		if (selection != null) new ashui.reactive.Watch(() -> selection.id.get(), id -> {
			if (drag != null && drag.region.id != id) finish(true);
		});
		Owner.onCleanup(() -> { finish(false); phase.dispose(); segments = []; arms = []; });
	}

	function hover(handle:Int):Void {
		switch phase.state.get() {
			case Idle if (handle < 0): return;
			case Hover(now) if (now == handle): return;
			case Rotating(_): return;
			case _:
		}
		phase.send(PointAt(handle));
	}

	function move(x:Float, y:Float):Void {
		var d = drag;
		if (d == null || (x == d.last.x && y == d.last.y)) return;
		var vector = planeVector(d.camera, x, y, d.width, d.height, d.pivot, d.axis);
		var angle = Math.atan2(d.center.y - y, x - d.center.x), delta:Float;
		if (Math.abs(d.axis.dot(d.camera.eye.sub(d.camera.target).normalize())) < 0.15) {
			// An edge-on ring has no stable ray/plane intersection. Follow its projected tangent.
			var tangent = d.axis.cross(d.vector != null ? d.vector : d.camera.eye.sub(d.pivot).normalize());
			var end = project(d.camera, d.pivot.add(tangent), d.width, d.height);
			var tx = end != null ? end.x - d.center.x : 1, ty = end != null ? end.y - d.center.y : 0;
			var length = Math.sqrt(tx * tx + ty * ty);
			delta = length > 1e-5 ? ((x - d.last.x) * tx + (y - d.last.y) * ty) / length / minRadius : 0;
			vector = d.vector != null ? Quat.axisAngle(d.axis, delta).rotate(d.vector) : null;
		} else if (vector != null && d.vector != null)
			delta = Math.atan2(d.axis.dot(d.vector.cross(vector)), d.vector.dot(vector));
		else {
			delta = angle - d.angle;
			if (delta > Math.PI) delta -= Math.PI * 2;
			if (delta < -Math.PI) delta += Math.PI * 2;
		}
		d.vector = vector; d.angle = angle; d.last = {x: x, y: y};
		if (Math.isFinite(delta) && Math.abs(delta) > 1e-8) {
			d.total += delta;
			d.rotate(Quat.axisAngle(d.axis, delta));
		}
	}

	/** Cached inverse view projection: no new camera matrices per ring vertex. **/
	function projectPoint(point:Vec3):Null<Point> {
		var p = view.transformPoint(point), depth = -p.z;
		return depth < viewed.near || depth > viewed.far ? null : {x: width / 2 + p.x * focal / depth, y: height / 2 - p.y * focal / depth};
	}

	/** Sample native local coordinates once on grab, preserving CSS scale/rotation during capture outside the canvas. **/
	static function pointerMap(node:ashui.layout.Node, x:Float, y:Float, localX:Float, localY:Float):Affine {
		function sample(dx:Float, dy:Float):Null<Point> {
			for (hit in node.tree.hitTest(x + dx, y + dy)) if (hit.id == node.id) return {x: hit.x, y: hit.y};
			return null;
		}
		var sx = 1.0, sy = 1.0, px = sample(1, 0), py = sample(0, 1);
		if (px == null) { px = sample(-1, 0); sx = -1; }
		if (py == null) { py = sample(0, -1); sy = -1; }
		var a = px != null ? (px.x - localX) / sx : 1, b = px != null ? (px.y - localY) / sx : 0;
		var c = py != null ? (py.x - localX) / sy : 0, d = py != null ? (py.y - localY) / sy : 1;
		return new Affine(a, b, c, d, localX - a * x - c * y, localY - b * x - d * y);
	}

	function finish(cancel:Bool):Void {
		if (hook != null) Pointer.hooks.remove(hook);
		hook = null;
		var d = drag; drag = null;
		if (cancel && d != null && d.total != 0) d.rotate(Quat.axisAngle(d.axis, -d.total));
		phase.send(Finish);
	}

	/** Positive or negative X/Y/Z view, preserving the orbit target and distance. **/
	public function snapView(handle:Int):Void {
		if (handle < 4 || handle > 9) return;
		var axis = Std.int((handle - 4) / 2), positive = (handle & 1) == 1;
		if (axis == 0) { camera.azimuth.set(positive ? Math.PI / 2 : -Math.PI / 2); camera.elevation.set(0); }
		if (axis == 1) { camera.azimuth.set(0); camera.elevation.set(positive ? camera.maxElevation : -camera.maxElevation); }
		if (axis == 2) { camera.azimuth.set(positive ? 0 : Math.PI); camera.elevation.set(0); }
	}

	/** World point in a canvas, or null outside the depth range. **/
	public static function project(camera:Camera, point:Vec3, width:Float, height:Float):Null<Point> {
		if (width <= 0 || height <= 0) return null;
		var forward = camera.target.sub(camera.eye).normalize(), right = forward.cross(camera.up).normalize(), up = right.cross(forward);
		var v = point.sub(camera.eye), depth = v.dot(forward);
		if (depth < camera.near || depth > camera.far) return null;
		var scale = height / (2 * Math.tan(camera.fovY / 2) * depth);
		return {x: width / 2 + v.dot(right) * scale, y: height / 2 - v.dot(up) * scale};
	}

	public static function ray(camera:Camera, x:Float, y:Float, width:Float, height:Float):{origin:Vec3, direction:Vec3} {
		var forward = camera.target.sub(camera.eye).normalize(), right = forward.cross(camera.up).normalize(), up = right.cross(forward);
		var scale = 2 * Math.tan(camera.fovY / 2) / height;
		return {origin: camera.eye, direction: forward.add(right.scale((x - width / 2) * scale)).add(up.scale((height / 2 - y) * scale)).normalize()};
	}

	static function planeVector(camera:Camera, x:Float, y:Float, width:Float, height:Float, pivot:Vec3, axis:Vec3):Null<Vec3> {
		var r = ray(camera, x, y, width, height), divisor = r.direction.dot(axis);
		if (Math.abs(divisor) < 1e-5) return null;
		var t = pivot.sub(r.origin).dot(axis) / divisor;
		if (t <= 0) return null;
		var v = r.origin.add(r.direction.scale(t)).sub(pivot);
		return v.length() < 1e-6 ? null : v.normalize();
	}

	static function distance(a:Point, b:Point):Float {
		var x = a.x - b.x, y = a.y - b.y;
		return Math.sqrt(x * x + y * y);
	}
	static function lineDistance(x:Float, y:Float, a:Point, b:Point):Float {
		var dx = b.x - a.x, dy = b.y - a.y, length = dx * dx + dy * dy;
		var t = length > 0 ? Math.max(0, Math.min(1, ((x - a.x) * dx + (y - a.y) * dy) / length)) : 0;
		var ox = x - a.x - t * dx, oy = y - a.y - t * dy;
		return Math.sqrt(ox * ox + oy * oy);
	}
}
