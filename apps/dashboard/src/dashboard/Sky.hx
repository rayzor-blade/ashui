package dashboard;

import ashui.canvaskit.Skybox;
import ashui.draw3d.Fog;

/**
	The dashboard's sky, all the way round the car: the floor fades into a haze
	with distance, and the sky's horizon is that haze, so the floor and the
	sky meet without an edge from any side the camera turns to. Above the
	horizon the sky deepens to the zenith. `dark` is the night scheme's.
**/
class Sky {
	/** The haze the far floor fades into, which is the sky's horizon too. **/
	public final haze:Int;

	public final fog:Fog;
	public final skybox:Skybox;

	public function new(dark:Bool) {
		haze = dark ? 0x70747d : 0xe2e5ea;
		var zenith = dark ? 0x9a9fa8 : 0xc2c7d1;
		// Past the car and the rings, which are never fogged, to where the floor is all haze.
		fog = new Fog(haze, 16, 90);
		skybox = Gradient(zenith, haze, haze);
	}
}
