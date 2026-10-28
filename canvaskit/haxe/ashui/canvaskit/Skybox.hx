package ashui.canvaskit;

/**
	Display settings for a panorama.

	- `intensity`: brightness multiplier, default 1.
	- `turn`: rotation around the vertical axis in radians, default 0.
	- `upsideDown`: flips images whose top row represents the ground.
	- `radius` and `centre`: project inside a finite sphere for parallax while
	  orbiting. By default the panorama is infinitely distant and responds
	  only to camera rotation.
	- `spread`: sky coverage multiplier relative to the camera lens, default 1.
	  Larger values make the sky appear farther away.
**/
typedef PanoramaOptions = {
	?intensity:Float,
	?turn:Float,
	?upsideDown:Bool,
	?centre:ashui.math.Vec3,
	?radius:Float,
	?spread:Float
};

/**
	Background of a 3D scene, displayed wherever meshes leave the canvas clear.
	Use with `<scene-kit skybox={...}>` or a `SkyboxPass`.

	```haxe
	skybox={Sky(night, 0.3)}                     // blurred environment
	skybox={Grounded(studio, 1.7, 20, 0)}        // environment with a floor
	skybox={Panorama(milkyWay)}                  // full-resolution image
	skybox={Gradient(0x6aa0ff, 0xe8eef8, 0x404040)}
	```
**/
enum Skybox {
	/** Displays an environment map. `blur` ranges from zero (sharp) to one (most blurred); `intensity` scales brightness. **/
	Sky(environment:Environment, ?blur:Float, ?intensity:Float);

	/**
		Projects the lower environment onto a ground plane. `height` is the
		original panorama camera height, `floor` is the ground height (default 0),
		and `radius` sets where the ground curves into the sky. `blur` and
		`intensity` use the same values as `Sky`.
	**/
	Grounded(environment:Environment, height:Float, radius:Float, ?floor:Float, ?blur:Float, ?intensity:Float);

	/**
		Displays a full-resolution 2:1 equirectangular image covering all directions.
		Preserves source colors without exposure or tone mapping. Useful for
		photos and paintings that a cubemap would soften. Fog affects only a
		band near the horizon. See `PanoramaOptions`.
	**/
	Panorama(image:ashui.types.Bitmap, ?options:PanoramaOptions);

	/** Creates a sky gradient from `zenith` overhead through `horizon` to `ground`, using `0xRRGGBB` colors. **/
	Gradient(zenith:Int, horizon:Int, ground:Int);
}
