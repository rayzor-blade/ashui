package ashui.canvaskit;

/**
	What a 3D scene shows behind its meshes, where they leave the canvas
	uncovered, as `<scene-kit skybox={...}>` takes it (drawn by a
	`SkyboxPass`):

	```haxe
	skybox={Sky(night, 0.3)}                     // an environment, a little blurred
	skybox={Grounded(studio, 1.7, 20, 0)}        // its floor laid under the scene
	skybox={Gradient(0x6aa0ff, 0xe8eef8, 0x404040)}  // colours, by height
	```
**/
enum Skybox {
	/** `environment` seen from the eye, `blur` 0 sharp to 1 its blurriest, its light times `intensity`. **/
	Sky(environment:Environment, ?blur:Float, ?intensity:Float);

	/**
		`environment` with its lower half laid on the ground, so a sky with a
		floor in it has that floor under the scene rather than infinitely far
		below: seen from where its camera stood, `height` above a floor at
		`floor` (0 by default) under the origin, the floor reaching `radius`
		round it before the sky curves up. `blur` and `intensity` as `Sky`'s.
	**/
	Grounded(environment:Environment, height:Float, radius:Float, ?floor:Float, ?blur:Float, ?intensity:Float);

	/** From `zenith` overhead through `horizon` round the level to `ground` below, `0xRRGGBB`. **/
	Gradient(zenith:Int, horizon:Int, ground:Int);
}
