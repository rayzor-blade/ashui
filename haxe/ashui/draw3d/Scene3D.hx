package ashui.draw3d;

import ashui.math.Vec3;

/**
	What meshes are drawn under: the camera, the lights, the light that
	reaches everywhere (`ambient`, a colour and how strong), the exposure
	the result is shown at, and what is behind them, `background` at
	`backgroundAlpha` (by default nothing: the canvas shows through).

	An `environment` lights them from all round instead of `ambient`, and
	is what they reflect, at `environmentIntensity`. A `skybox` is drawn
	behind them: an environment or colours (see `Skybox`), and a `grid`
	under them (see `GroundGrid`). Immutable; `with` makes a changed copy.
**/
class Scene3D {
	public static final DEFAULT = new Scene3D(new Camera(new Vec3(0, 1.5, 4), Vec3.ZERO), [Directional(new Vec3(-0.4, -1, -0.3), 0xffffff, 2.5)], 0xffffff,
		0.25, 1, 0x000000, 0);

	public final camera:Camera;
	public final lights:Array<Light>;
	public final ambient:Int;
	public final ambientStrength:Float;
	public final exposure:Float;
	public final background:Int;
	public final backgroundAlpha:Float;
	public final environment:Null<Environment>;
	public final environmentIntensity:Float;
	public final skybox:Null<Skybox>;
	public final grid:Null<GroundGrid>;

	public function new(camera:Camera, lights:Array<Light>, ambient:Int, ambientStrength:Float, exposure:Float, background:Int, backgroundAlpha:Float,
			?environment:Environment, environmentIntensity = 1.0, ?skybox:Skybox, ?grid:GroundGrid) {
		this.grid = grid;
		this.environment = environment;
		this.environmentIntensity = environmentIntensity;
		this.skybox = skybox;
		this.camera = camera;
		this.lights = lights;
		this.ambient = ambient;
		this.ambientStrength = ambientStrength;
		this.exposure = exposure;
		this.background = background;
		this.backgroundAlpha = backgroundAlpha;
	}

	public function with(?camera:Camera, ?lights:Array<Light>, ?ambient:Int, ?ambientStrength:Float, ?exposure:Float, ?background:Int,
			?backgroundAlpha:Float, ?environment:Environment, ?environmentIntensity:Float, ?skybox:Skybox, ?grid:GroundGrid):Scene3D
		return new Scene3D(camera != null ? camera : this.camera, lights != null ? lights : this.lights, ambient != null ? ambient : this.ambient,
			ambientStrength != null ? ambientStrength : this.ambientStrength, exposure != null ? exposure : this.exposure,
			background != null ? background : this.background, backgroundAlpha != null ? backgroundAlpha : this.backgroundAlpha,
			environment != null ? environment : this.environment, environmentIntensity != null ? environmentIntensity : this.environmentIntensity,
			skybox != null ? skybox : this.skybox, grid != null ? grid : this.grid);
}
