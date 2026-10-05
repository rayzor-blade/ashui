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

	With `shadows`, its first light casts them, if it is directional: the
	light's view is fitted round the scene's meshes each render, into a map
	`size` pixels square (2048 by default), `strength` dark (0.7), with
	`bias` keeping surfaces from shadowing themselves.
**/
class LightRig implements SceneLighting {
	public final rig:Array<Light>;
	public final ambient:Int;
	public final strength:Float;
	public final sky:Null<Environment>;
	public final skyIntensity:Float;
	public final shadowOptions:Null<{?size:Int, ?strength:Float, ?bias:Float}>;

	var settled:Null<ShadowSettings> = null;

	public function new(lights:Array<Light>, ambient = 0xffffff, ambientStrength = 0.25, ?environment:Environment, environmentIntensity = 1.0,
			?shadows:{?size:Int, ?strength:Float, ?bias:Float}) {
		shadowOptions = shadows;
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

	public function shadows():Null<ShadowSettings>
		return settled;

	/** The first light's shadows, its view an orthographic box round `min` to `max` along its direction; null without a directional first light. **/
	function fitShadows(min:ashui.math.Vec3, max:ashui.math.Vec3):Null<ShadowSettings> {
		if (shadowOptions == null || rig.length == 0)
			return null;
		var direction = switch rig[0] {
			case Directional(d, _, _): d.normalize();
			case _: return null;
		}
		var centre = min.lerp(max, 0.5);
		var radius = Math.max(0.01, max.sub(min).length() / 2);
		var eye = centre.sub(direction.scale(radius * 2));
		var up = Math.abs(direction.y) > 0.99 ? new ashui.math.Vec3(1, 0, 0) : ashui.math.Vec3.UP;
		var view = ashui.math.Mat4.lookAt(eye, centre, up);
		var projection = ashui.math.Mat4.orthographic(-radius, radius, -radius, radius, radius * 0.5, radius * 3.5);
		var o = shadowOptions;
		return {
			viewProjection: projection.mul(view),
			size: o.size != null ? o.size : 2048,
			strength: o.strength != null ? o.strength : 0.7,
			bias: o.bias != null ? o.bias : 0.004
		};
	}

	#if ashui_gpu
	var map:Null<EnvironmentMap> = null;

	public function prepare(frame:ScenePassFrame):Void {
		map = sky != null ? {view: sky.upload(frame.device), levels: sky.levels, intensity: skyIntensity} : null;
		settled = fitShadows(frame.bounds.min, frame.bounds.max);
	}

	public function environment():Null<EnvironmentMap>
		return map;
	#else
	public function prepare(frame:ScenePassFrame):Void {}

	public function environment():Null<EnvironmentMap>
		return null;
	#end
}
