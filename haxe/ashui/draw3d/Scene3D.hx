package ashui.draw3d;

import ashui.math.Vec3;

/**
	What meshes are drawn under: the camera, the `lighting` (see
	`SceneLighting`), the exposure the result is shown at, and what is
	behind them, `background` at `backgroundAlpha` (by default nothing: the
	canvas shows through). Immutable; `with` makes a changed copy.
**/
class Scene3D {
	public static final DEFAULT = new Scene3D(new Camera(new Vec3(0, 1.5, 4), Vec3.ZERO),
		new SceneLighting.BasicLighting([Directional(new Vec3(-0.4, -1, -0.3), 0xffffff, 2.5)]), 1, 0x000000, 0);

	public final camera:Camera;
	public final lighting:SceneLighting;
	public final exposure:Float;
	public final background:Int;
	public final backgroundAlpha:Float;

	public function new(camera:Camera, lighting:SceneLighting, exposure = 1.0, background = 0x000000, backgroundAlpha = 0.0) {
		this.camera = camera;
		this.lighting = lighting;
		this.exposure = exposure;
		this.background = background;
		this.backgroundAlpha = backgroundAlpha;
	}

	public function with(?camera:Camera, ?lighting:SceneLighting, ?exposure:Float, ?background:Int, ?backgroundAlpha:Float):Scene3D
		return new Scene3D(camera != null ? camera : this.camera, lighting != null ? lighting : this.lighting, exposure != null ? exposure : this.exposure,
			background != null ? background : this.background, backgroundAlpha != null ? backgroundAlpha : this.backgroundAlpha);
}
