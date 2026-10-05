package ashui.canvaskit;

/**
	What a 3D scene shows behind its meshes, where they leave the canvas
	uncovered, as `<scene-kit skybox={...}>` takes it (drawn by a
	`SkyboxPass`):

	```haxe
	skybox={Sky(night, 0.3)}                     // an environment, a little blurred
	skybox={Grounded(studio, 1.7, 20, 0)}        // its floor laid under the scene
	skybox={Panorama(milkyWay)}                  // an image, shown as it is
	skybox={Gradient(0x6aa0ff, 0xe8eef8, 0x404040)}  // colours, by height
	```
**/
/**
	Options for how a `Panorama` is shown.

	- `intensity` scales its brightness (default 1).
	- `turn` rotates it about the vertical, in radians (default 0).
	- `upsideDown` is for an image whose top row is what lies below.
	- `radius` and `centre`: by default the panorama is infinitely far away
	  and only moves when the camera turns. With a radius, it is painted on
	  the inside of a sphere of that radius around `centre`, with the camera
	  inside. Orbiting then moves the near side of the sphere past the far
	  side, which gives the sky depth, as in a model viewer.
	- `spread` shows that many times more sky through each pixel than the
	  camera's lens would, making the sky look further away (default 1).
**/
typedef PanoramaOptions = {
	?intensity:Float,
	?turn:Float,
	?upsideDown:Bool,
	?centre:ashui.math.Vec3,
	?radius:Float,
	?spread:Float
};

enum Skybox {
	/** `environment` seen from the eye, `blur` 0 sharp to 1 its blurriest, its light times `intensity`. **/
	Sky(environment:Environment, ?blur:Float, ?intensity:Float);

	/**
		`environment` with its lower half projected onto the ground. A sky
		photographed with a floor in it then has that floor under the scene,
		instead of infinitely far below. `height` is how high the sky's camera
		was above the floor, `floor` is the floor's height (0 by default), and
		`radius` is how far the floor reaches before the sky curves up. `blur`
		and `intensity` work as they do for `Sky`.
	**/
	Grounded(environment:Environment, height:Float, radius:Float, ?floor:Float, ?blur:Float, ?intensity:Float);

	/**
		An equirectangular `image`, shown as it is: twice as wide as it is tall,
		running all the way around from left to right and from straight up to
		straight down from top to bottom. It is sampled at its full resolution,
		and its colours are not changed by exposure or tone mapping. Use it for
		a photo or painting of a sky, which a cubemap made from it would
		soften. Fog only tints a band near its horizon, where the far ground's
		haze meets it. See `PanoramaOptions`.
	**/
	Panorama(image:ashui.types.Bitmap, ?options:PanoramaOptions);

	/** From `zenith` overhead through `horizon` round the level to `ground` below, `0xRRGGBB`. **/
	Gradient(zenith:Int, horizon:Int, ground:Int);
}
