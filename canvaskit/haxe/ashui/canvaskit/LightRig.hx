package ashui.canvaskit;

import ashui.draw3d.Light;
import ashui.draw3d.ScenePass;
import ashui.draw3d.SceneLighting;

/**
	A scene's lighting as a studio sets it up: its lights, the light that
	reaches everywhere, and an `Environment`, a sky that lights the meshes
	from all round, at `environmentIntensity`, and that they reflect.
	`<scene-kit>` makes one from its `lights`, `ambient` and `environment`;
	a canvas sets one with `ctx.setLighting(rig)`.
**/
class LightRig implements SceneLighting {
	public final rig:Array<Light>;
	public final ambient:Int;
	public final strength:Float;
	public final sky:Null<Environment>;
	public final skyIntensity:Float;

	public function new(lights:Array<Light>, ambient = 0xffffff, ambientStrength = 0.25, ?environment:Environment, environmentIntensity = 1.0) {
		rig = lights;
		this.ambient = ambient;
		strength = ambientStrength;
		sky = environment;
		skyIntensity = environmentIntensity;
	}

	public function lights():Array<Light>
		return rig;

	public function ambientColor():Int
		return ambient;

	public function ambientStrength():Float
		return strength;

	#if ashui_gpu
	var map:Null<EnvironmentMap> = null;

	public function prepare(frame:ScenePassFrame):Void
		map = sky != null ? {view: sky.upload(frame.device), levels: sky.levels, intensity: skyIntensity} : null;

	public function environment():Null<EnvironmentMap>
		return map;
	#else
	public function prepare(frame:ScenePassFrame):Void {}

	public function environment():Null<EnvironmentMap>
		return null;
	#end
}
