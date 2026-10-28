package ashui.draw3d;

import ashui.math.Vec3;

/**
	Immutable settings for rendering a 3D scene. Use `with` to create a
	modified copy.

	- `camera`, `lighting` and `exposure` control the view and illumination.
	- `background` and `backgroundAlpha` set the clear color. The canvas
	  shows through by default.
	- `fog` fades distant geometry. `bloom` and `grade` add post-processing.
	- `lens` controls fisheye distortion: 0 disables it; larger values bend more.
	- `vignette` darkens edges and corners, from 0 to 1.
	- `grain` adds film grain, from 0 (none) to 1 (heavy).
	- `aberration` adds edge color fringes, from 0 (none) to 1 (strong).
	- `antialias` enables FXAA.
	- `motionBlur` sets shutter duration as a fraction of a frame, from 0 to 1.
	  Fast-moving or rotating meshes blur along their motion.

	See `SceneLighting` for lighting configuration.
**/
class Scene3D {
	public static final DEFAULT = new Scene3D(new Camera(new Vec3(0, 1.5, 4), Vec3.ZERO),
		new SceneLighting.BasicLighting([Directional(new Vec3(-0.4, -1, -0.3), 0xffffff, 2.5)]), 1, 0x000000, 0);

	public final camera:Camera;
	public final lighting:SceneLighting;
	public final exposure:Float;
	public final background:Int;
	public final backgroundAlpha:Float;
	public final fog:Null<Fog>;
	public final lens:Float;
	public final bloom:Null<Bloom>;
	public final vignette:Float;
	public final grain:Float;
	public final aberration:Float;
	public final grade:Null<ColorGrade>;
	public final antialias:Bool;
	public final motionBlur:Float;

	public function new(camera:Camera, lighting:SceneLighting, exposure = 1.0, background = 0x000000, backgroundAlpha = 0.0, ?fog:Fog, lens = 0.0,
			?bloom:Bloom, vignette = 0.0, grain = 0.0, aberration = 0.0, ?grade:ColorGrade, antialias = false, motionBlur = 0.0) {
		this.camera = camera;
		this.lighting = lighting;
		this.exposure = exposure;
		this.background = background;
		this.backgroundAlpha = backgroundAlpha;
		this.fog = fog;
		this.lens = lens;
		this.bloom = bloom;
		this.vignette = vignette;
		this.grain = grain;
		this.aberration = aberration;
		this.grade = grade;
		this.antialias = antialias;
		this.motionBlur = motionBlur;
	}

	public function with(?camera:Camera, ?lighting:SceneLighting, ?exposure:Float, ?background:Int, ?backgroundAlpha:Float, ?fog:Fog, ?lens:Float,
			?bloom:Bloom, ?vignette:Float, ?grain:Float, ?aberration:Float, ?grade:ColorGrade, ?antialias:Bool, ?motionBlur:Float):Scene3D
		return new Scene3D(camera != null ? camera : this.camera, lighting != null ? lighting : this.lighting, exposure != null ? exposure : this.exposure,
			background != null ? background : this.background, backgroundAlpha != null ? backgroundAlpha : this.backgroundAlpha, fog != null ? fog : this.fog,
			lens != null ? lens : this.lens, bloom != null ? bloom : this.bloom, vignette != null ? vignette : this.vignette,
			grain != null ? grain : this.grain, aberration != null ? aberration : this.aberration, grade != null ? grade : this.grade,
			antialias != null ? antialias : this.antialias, motionBlur != null ? motionBlur : this.motionBlur);
}
