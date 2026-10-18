import ashui.canvaskit.Skybox;
import ashui.draw3d.Fog;

/**
	The banner's sky, all the way round the car: the floor fades into a haze
	with distance, and the sky's horizon is that haze, so the floor and the
	sky meet without an edge from any side the camera turns to. Above the
	horizon the sky deepens to the zenith. `dark` is the night scheme's.
**/
class BannerSky {
	/** The haze the far floor fades into, which is the sky's horizon too. **/
	public final haze:Int;

	public final fog:Fog;
	public final skybox:Skybox;

	public function new(dark:Bool) {
		haze = dark ? 0x2b3548 : 0xe8edf4;
		var zenith = dark ? 0x04060b : 0x9db8e0;
		// Past the car and the rings, which are never fogged, to where the floor is all haze.
		fog = new Fog(haze, 16, 90);
		skybox = Gradient(zenith, haze, haze);
	}
}
