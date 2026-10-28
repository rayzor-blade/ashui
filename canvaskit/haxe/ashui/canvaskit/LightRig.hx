package ashui.canvaskit;

import ashui.draw3d.Light;
import ashui.draw3d.ScenePass;
import ashui.draw3d.SceneLighting;

/**
	Shadow settings for the first light, when directional.

	- `size`: shadow-map width and height in pixels; defaults to 2048.
	- `strength`: fraction of direct light blocked; defaults to 0.7.
	- `bias`: offset to reduce self-shadowing; defaults to 0.004.
	- `reach` and `focus`: limit shadow coverage around a point for sharper
	  shadows in a wide scene.
**/
typedef ShadowOptions = {?size:Int, ?strength:Float, ?bias:Float, ?reach:Float, ?focus:ashui.math.Vec3};

/**
	Scene lights, ambient light, and environment lighting in one rig.
	`SceneKit` creates a rig from its lighting props; custom canvases can
	apply one with `ctx.setLighting(rig)`. An `Environment` supplies reflections
	and diffuse light, scaled by `environmentIntensity`.

	With shadow options, the first light casts shadows when directional.
	Coverage fits the scene meshes on each render, optionally limited by
	`reach` and `focus`. See `ShadowOptions` for resolution, strength, and bias.
**/
class LightRig implements SceneLighting {
	public final rig:Array<Light>;
	public final ambient:Int;
	public final strength:Float;
	public final sky:Null<Environment>;
	public final skyIntensity:Float;
	public final shadowOptions:Null<ShadowOptions>;

	var settled:Null<ShadowSettings> = null;

	public function new(lights:Array<Light>, ambient = 0xffffff, ambientStrength = 0.25, ?environment:Environment, environmentIntensity = 1.0,
			?shadows:ShadowOptions) {
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

	/**
		Fits an orthographic shadow view around scene bounds, optionally limited
		by `reach` around `focus`. Returns null without a directional first light.
	**/
	function fitShadows(min:ashui.math.Vec3, max:ashui.math.Vec3):Null<ShadowSettings> {
		if (shadowOptions == null || rig.length == 0)
			return null;
		var reach = shadowOptions.reach, focus = shadowOptions.focus;
		if (reach != null && focus != null) {
			// The scene's box cut down to the reach round the focus; the reach alone where they do not meet.
			var lo = new ashui.math.Vec3(Math.max(min.x, focus.x - reach), Math.max(min.y, focus.y - reach), Math.max(min.z, focus.z - reach));
			var hi = new ashui.math.Vec3(Math.min(max.x, focus.x + reach), Math.min(max.y, focus.y + reach), Math.min(max.z, focus.z + reach));
			if (lo.x > hi.x || lo.y > hi.y || lo.z > hi.z) {
				lo = focus.sub(new ashui.math.Vec3(reach, reach, reach));
				hi = focus.add(new ashui.math.Vec3(reach, reach, reach));
			}
			min = lo;
			max = hi;
		}
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
