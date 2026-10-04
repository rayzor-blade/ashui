package ashui.canvaskit;

import ashui.draw3d.Camera;
import ashui.math.Vec3;
import ashui.reactive.Signal;

/**
	A camera that circles a target: turned about it by `azimuth` (radians
	round the vertical, 0 looking down -Z) and raised by `elevation`
	(radians above the level), `distance` away. Each is a signal, so a
	canvas that reads `camera()` while drawing draws again when the camera
	moves, and only then.

	`orbit`, `zoom` and `pan` move it as a drag, a scroll and a
	shift-drag do in `SceneKit3D`.
**/
class OrbitCamera {
	public final azimuth:Signal<Float>;
	public final elevation:Signal<Float>;
	public final distance:Signal<Float>;
	public final target:Signal<Vec3>;
	public final fovY:Signal<Float>;

	/** How near and how far it may come. **/
	public var minDistance = 0.2;

	public var maxDistance = 200.0;

	/** How far above and below the level it may go: a little short of straight up or down, where the view would turn over. **/
	public var maxElevation = 1.55;

	final initial:{azimuth:Float, elevation:Float, distance:Float, target:Vec3};

	public function new(azimuth = 0.4, elevation = 0.3, distance = 4.0, ?target:Vec3, fovY = 0.8) {
		var t = target != null ? target : Vec3.ZERO;
		this.azimuth = Signal.make(azimuth);
		this.elevation = Signal.make(elevation);
		this.distance = Signal.make(distance);
		this.target = Signal.make(t);
		this.fovY = Signal.make(fovY);
		initial = {azimuth: azimuth, elevation: elevation, distance: distance, target: t};
	}

	/** Where it is. **/
	public function eye():Vec3 {
		var a = azimuth.get(), e = elevation.get(), d = distance.get();
		var c = Math.cos(e);
		return target.get().add(new Vec3(Math.sin(a) * c * d, Math.sin(e) * d, Math.cos(a) * c * d));
	}

	/** The camera to draw with; read while drawing, it is followed. **/
	public function camera():Camera
		return new Camera(eye(), target.get(), null, fovY.get(), Math.max(0.01, distance.get() * 0.01), Math.max(100, distance.get() * 50));

	/** Turned round the target by `dAzimuth` and raised by `dElevation`, in radians. **/
	public function orbit(dAzimuth:Float, dElevation:Float):Void {
		azimuth.set(azimuth.get() + dAzimuth);
		elevation.set(Math.max(-maxElevation, Math.min(maxElevation, elevation.get() + dElevation)));
	}

	/** Nearer by `factor` below 1, further above it. **/
	public function zoom(factor:Float):Void
		distance.set(Math.max(minDistance, Math.min(maxDistance, distance.get() * factor)));

	/**
		The target moved across the view, `dx` right and `dy` up, in
		fractions of the view's height at the target, so a drag across the
		whole view moves it as far as the view is high there.
	**/
	public function pan(dx:Float, dy:Float):Void {
		var eye = this.eye(), t = target.get();
		var forward = t.sub(eye).normalize();
		var right = forward.cross(Vec3.UP).normalize();
		var up = right.cross(forward);
		var height = 2 * distance.get() * Math.tan(fovY.get() / 2);
		target.set(t.add(right.scale(dx * height)).add(up.scale(dy * height)));
	}

	/** Back where it began. **/
	public function reset():Void {
		azimuth.set(initial.azimuth);
		elevation.set(initial.elevation);
		distance.set(initial.distance);
		target.set(initial.target);
	}

	/** Placed to see the box from `min` to `max` whole, from where it looks now. **/
	public function frame(min:Vec3, max:Vec3):Void {
		target.set(min.lerp(max, 0.5));
		var radius = max.sub(min).length() / 2;
		distance.set(Math.max(minDistance, Math.min(maxDistance, radius / Math.sin(fovY.get() / 2) * 1.1)));
	}
}
