package ashui.canvaskit;

/**
	What a 3D scene shows behind its meshes, where they leave the canvas
	uncovered, as `<scene-kit skybox={...}>` takes it (drawn by a
	`SkyboxPass`):

	```haxe
	skybox={Sky(night, 0.3)}                     // an environment, a little blurred
	skybox={Gradient(0x6aa0ff, 0xe8eef8, 0x404040)}  // colours, by height
	```
**/
enum Skybox {
	/** `environment` seen from the eye, `blur` 0 sharp to 1 its blurriest, its light times `intensity`. **/
	Sky(environment:Environment, ?blur:Float, ?intensity:Float);

	/** From `zenith` overhead through `horizon` round the level to `ground` below, `0xRRGGBB`. **/
	Gradient(zenith:Int, horizon:Int, ground:Int);
}
