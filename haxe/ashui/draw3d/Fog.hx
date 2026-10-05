package ashui.draw3d;

/**
	Air a scene's meshes fade into with distance: clear nearer the eye than
	`near`, wholly `color` (`0xRRGGBB`) from `far` on, eased between. It
	hides where a scene ends and gives it depth; a sky's horizon fades into
	it too, so ground and sky meet in it.
**/
class Fog {
	public final color:Int;
	public final near:Float;
	public final far:Float;

	public function new(color:Int, near:Float, far:Float) {
		this.color = color;
		this.near = near;
		this.far = far;
	}
}
