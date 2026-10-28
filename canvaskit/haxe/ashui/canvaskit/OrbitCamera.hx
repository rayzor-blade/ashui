package ashui.canvaskit;

import ashui.draw3d.Camera;
import ashui.math.Vec3;
import ashui.reactive.Signal;

/**
	A reactive camera orbiting a target.
	`azimuth` rotates around the vertical axis in radians, with zero looking
	down -Z. `elevation` sets radians above the horizontal, and `distance`
	sets the target distance. These values are signals; drawing callbacks
	that read `camera()` redraw when the camera changes.

	`orbit`, `zoom`, and `pan` support the drag and scroll controls in `SceneKit`.
**/
class OrbitCamera {
	public final azimuth:Signal<Float>;
	public final elevation:Signal<Float>;
	public final distance:Signal<Float>;
	public final target:Signal<Vec3>;
	public final fovY:Signal<Float>;

	/** Minimum target distance. `maxDistance` limits the maximum. **/
	public var minDistance = 0.2;

	public var maxDistance = 200.0;

	/** Maximum absolute elevation in radians, stopping short of vertical to prevent the view from flipping. **/
	public var maxElevation = 1.55;

	final initial:{
		azimuth:Float,
		elevation:Float,
		distance:Float,
		target:Vec3
	};

	public function new(azimuth = 0.4, elevation = 0.3, distance = 4.0, ?target:Vec3, fovY = 0.8) {
		var t = target != null ? target : Vec3.ZERO;
		this.azimuth = Signal.make(azimuth);
		this.elevation = Signal.make(elevation);
		this.distance = Signal.make(distance);
		this.target = Signal.make(t);
		this.fovY = Signal.make(fovY);
		initial = {
			azimuth: azimuth,
			elevation: elevation,
			distance: distance,
			target: t
		};
	}

	/** Returns the camera world position. **/
	public function eye():Vec3 {
		var a = azimuth.get(), e = elevation.get(), d = distance.get();
		var c = Math.cos(e);
		return target.get().add(new Vec3(Math.sin(a) * c * d, Math.sin(e) * d, Math.cos(a) * c * d));
	}

	/** Returns the drawing camera. Reactive readers subscribe to camera changes. **/
	public function camera():Camera
		return new Camera(eye(), target.get(), null, fovY.get(), Math.max(0.01, distance.get() * 0.01), Math.max(100, distance.get() * 50));

	/** Rotates around the target by azimuth and elevation deltas in radians. **/
	public function orbit(dAzimuth:Float, dElevation:Float):Void {
		azimuth.set(azimuth.get() + dAzimuth);
		elevation.set(Math.max(-maxElevation, Math.min(maxElevation, elevation.get() + dElevation)));
	}

	/** Multiplies the target distance by `factor`: below one moves closer, above one moves farther. **/
	public function zoom(factor:Float):Void
		distance.set(Math.max(minDistance, Math.min(maxDistance, distance.get() * factor)));

	/**
		Moves the target right by `dx` and up by `dy`, measured as fractions
		of the view height at the target distance.
	**/
	public function pan(dx:Float, dy:Float):Void {
		var eye = this.eye(), t = target.get();
		var forward = t.sub(eye).normalize();
		var right = forward.cross(Vec3.UP).normalize();
		var up = right.cross(forward);
		var height = 2 * distance.get() * Math.tan(fovY.get() / 2);
		target.set(t.add(right.scale(dx * height)).add(up.scale(dy * height)));
	}

	/** Restores the initial camera state. **/
	public function reset():Void {
		azimuth.set(initial.azimuth);
		elevation.set(initial.elevation);
		distance.set(initial.distance);
		target.set(initial.target);
	}

	/** Frames the box from `min` to `max` while preserving the viewing direction. **/
	public function frame(min:Vec3, max:Vec3):Void {
		target.set(min.lerp(max, 0.5));
		var radius = max.sub(min).length() / 2;
		distance.set(Math.max(minDistance, Math.min(maxDistance, radius / Math.sin(fovY.get() / 2) * 1.1)));
	}
}
