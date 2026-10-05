package ashui.draw3d;

#if ashui_gpu
/** An environment cubemap on the GPU, as a lighting hands it to ashui's mesh shader. **/
typedef EnvironmentMap = {view:gpu.GpuTextureView, levels:Int, intensity:Float};
#else
typedef EnvironmentMap = Dynamic;
#end

/**
	What lights a 3D scene's meshes: its lights, the light that reaches
	everywhere, and optionally an environment, a cubemap that lights them
	from all round and that they reflect. ashui's mesh shader reads them
	from the scene's buffer (see `ashui.shaders.Scene`); what makes them
	lives outside ashui's core. `BasicLighting` is lights and ambient light
	alone; ashui-canvaskit's `LightRig` adds an environment, built from an
	HDR sky.

	`prepare` runs before each render of the scene, the encoder free, to
	put on the GPU what `environment` then gives.
**/
interface SceneLighting {
	/** The lights; ashui's shader takes the first eight. **/
	function lights():Array<Light>;

	/** The light that reaches everywhere, `0xRRGGBB`. **/
	function ambientColor():Int;

	/** How strong the ambient light is. **/
	function ambientStrength():Float;

	/** Puts on the GPU what lighting needs, before the scene is drawn. **/
	function prepare(frame:ScenePass.ScenePassFrame):Void;

	/** The environment `prepare` made, or null: then ambient light stands in for it. **/
	function environment():Null<EnvironmentMap>;
}

/** Lights and ambient light, nothing else: what a scene has with no lighting of its own. **/
class BasicLighting implements SceneLighting {
	final list:Array<Light>;
	final color:Int;
	final strength:Float;

	public function new(lights:Array<Light>, ambient = 0xffffff, ambientStrength = 0.25) {
		list = lights;
		color = ambient;
		strength = ambientStrength;
	}

	public function lights():Array<Light>
		return list;

	public function ambientColor():Int
		return color;

	public function ambientStrength():Float
		return strength;

	public function prepare(frame:ScenePass.ScenePassFrame):Void {}

	public function environment():Null<EnvironmentMap>
		return null;
}
