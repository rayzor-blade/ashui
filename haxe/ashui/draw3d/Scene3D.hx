package ashui.draw3d;

import ashui.math.Vec3;

/**
	What meshes are drawn under: the camera, the `lighting` (see
	`SceneLighting`), the exposure the result is shown at, and what is
	behind them, `background` at `backgroundAlpha` (by default nothing: the
	canvas shows through), and the `fog` they fade into with distance, if
	any, the strength of the fish-eye `lens` it is seen through (0 for no
	lens; larger values bend more), its `bloom`, if any, its `vignette`
	(how much the edges and corners are darkened, from 0 for none to 1),
	its film `grain` (0 for none, 1 for heavy), and its chromatic
	`aberration` (0 for none, 1 for strong colour fringes at the edges). Immutable; `with` makes a changed copy.
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

	public function new(camera:Camera, lighting:SceneLighting, exposure = 1.0, background = 0x000000, backgroundAlpha = 0.0, ?fog:Fog, lens = 0.0, ?bloom:Bloom, vignette = 0.0,
			grain = 0.0, aberration = 0.0) {
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
	}

	public function with(?camera:Camera, ?lighting:SceneLighting, ?exposure:Float, ?background:Int, ?backgroundAlpha:Float, ?fog:Fog,
			?lens:Float, ?bloom:Bloom, ?vignette:Float, ?grain:Float, ?aberration:Float):Scene3D
		return new Scene3D(camera != null ? camera : this.camera, lighting != null ? lighting : this.lighting, exposure != null ? exposure : this.exposure,
			background != null ? background : this.background, backgroundAlpha != null ? backgroundAlpha : this.backgroundAlpha,
			fog != null ? fog : this.fog, lens != null ? lens : this.lens,
			bloom != null ? bloom : this.bloom, vignette != null ? vignette : this.vignette, grain != null ? grain : this.grain,
			aberration != null ? aberration : this.aberration);
}
