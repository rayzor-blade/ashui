package ashui.draw3d;

/**
	Bloom: bright light spilling onto its surroundings, as it does through
	a camera lens or in the eye. Parts of the scene's meshes brighter than
	`threshold` glow onto what is around them, scaled by `strength`.

	The threshold is measured in exposed light before tone mapping, where 1
	is white. So an emissive strip or a glint on metal glows, while ordinary
	lit surfaces, which stay under white, do not. A scene pass's own drawing
	does not glow.
**/
class Bloom {
	public final strength:Float;
	public final threshold:Float;

	public function new(strength = 0.6, threshold = 1.0) {
		this.strength = strength;
		this.threshold = threshold;
	}
}
