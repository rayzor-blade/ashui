package ashui.draw3d;

import ashui.math.Mat4;
import ashui.math.Vec3;

/**
	Where a 3D scene is seen from: an eye looking at a target, `up` keeping
	it level, through a perspective of `fovY` radians from the bottom of
	the view to its top. What is nearer than `near` or further than `far`
	is cut away. Immutable; `with` makes a changed copy.
**/
class Camera {
	public final eye:Vec3;
	public final target:Vec3;
	public final up:Vec3;
	public final fovY:Float;
	public final near:Float;
	public final far:Float;

	public function new(eye:Vec3, target:Vec3, ?up:Vec3, fovY = 0.8, near = 0.05, far = 500.0) {
		this.eye = eye;
		this.target = target;
		this.up = up != null ? up : Vec3.UP;
		this.fovY = fovY;
		this.near = near;
		this.far = far;
	}

	/** A copy with what is given changed. **/
	public function with(?eye:Vec3, ?target:Vec3, ?fovY:Float):Camera
		return new Camera(eye != null ? eye : this.eye, target != null ? target : this.target, up, fovY != null ? fovY : this.fovY, near, far);

	/** From the scene's coordinates to the camera's. **/
	public function view():Mat4
		return Mat4.lookAt(eye, target, up);

	/** From the camera's coordinates to the clip space of a view `aspect` wide for each unit high. **/
	public function projection(aspect:Float):Mat4
		return Mat4.perspective(fovY, aspect, near, far);
}
