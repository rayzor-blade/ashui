package ashui.draw3d;

/**
	Haze that a scene fades into with distance. Nothing nearer the eye than
	`near` is fogged. From `far` onwards, surfaces are covered by `color`
	(`0xRRGGBB`) as much as `opacity` allows, and between the two the fog
	eases in. With `opacity` below 1, the far scene still shows faintly
	through, as it does through real air.

	Fog hides where a scene ends and gives it depth. The sky's horizon fades
	into the same fog, so that ground and sky meet in it.
**/
class Fog {
	public final color:Int;
	public final near:Float;
	public final far:Float;
	public final opacity:Float;

	public function new(color:Int, near:Float, far:Float, opacity = 1.0) {
		this.color = color;
		this.near = near;
		this.far = far;
		this.opacity = opacity;
	}
}
