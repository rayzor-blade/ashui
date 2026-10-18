package dashboard;

import ashui.animation.AnimationScheduler;
import ashui.canvaskit.Environment;
import ashui.canvaskit.Geometry;
import ashui.canvaskit.OrbitCamera;
import ashui.canvaskit.Skybox;
import ashui.draw.DrawContext;
import ashui.draw3d.Fog;
import ashui.draw3d.Light;
import ashui.draw3d.Material;
import ashui.math.Mat4;
import ashui.math.Vec3;
import ashui.reactive.Computed;
import ashui.reactive.Signal;
import ashui.theme.ThemeState;

/** What is drawn for one scheme: the floor, the pool of accent light under the car, the rings, and the haze and sky it fades into. **/
private typedef World = {
	floor:ashui.draw3d.MeshData,
	pool:ashui.draw3d.MeshData,
	rings:Array<ashui.draw3d.MeshData>,
	haze:Int,
	fog:Fog,
	sky:Skybox,
	lights:Array<Light>,
	exposure:Float
};

/**
	The 3D world of the dashboard: the car standing on a floor that fades into a haze, under a sky that is the same haze at
	the horizon, lit as a photographer's studio is, in the light scheme and in the dark. It follows the colour scheme: what is
	drawn, the light and the sky are the scheme's, from the moment it changes. The second scheme's studio is made on a
	worker thread once the first frame is out, as a collection of the work it takes would stall one, and until it is there
	the first scheme's stands in.
**/
class Stage {
	public static inline var DISTANCE = 11.4;

	public final camera:OrbitCamera;
	public final car:Car3D;

	/** Whether the scheme is the dark one; changes only when the scheme does. **/
	public final dark:Computed<Bool>;

	public final environment:Computed<Null<Environment>>;
	public final fog:Computed<Fog>;
	public final skybox:Computed<Skybox>;
	public final background:Computed<Int>;
	public final lights:Computed<Array<Light>>;
	public final intensity:Computed<Float>;

	final worlds = new Map<Int, World>();
	final studios = Signal.make(new Map<Int, Environment>());
	final primary:Int;

	public function new(paint:Paint, toon:Bool) {
		car = new Car3D(paint.color, paint.metallic, toon);
		camera = new OrbitCamera(2.25, 0.38, DISTANCE, new Vec3(0.05, 0.62, 0.2), 0.5);
		var theme = ThemeState.get();
		primary = theme.color(Primary).rgb();
		dark = Computed.make(() -> {
			theme.revision.get();
			theme.scheme() == Dark;
		});
		environment = Computed.make(() -> {
			var made = studios.get();
			var own = made.get(key(dark.get()));
			own != null ? own : made.get(key(!dark.get()));
		});
		fog = Computed.make(() -> world(dark.get()).fog);
		skybox = Computed.make(() -> world(dark.get()).sky);
		background = Computed.make(() -> world(dark.get()).haze);
		lights = Computed.make(() -> world(dark.get()).lights);
		intensity = Computed.make(() -> dark.get() ? 1.0 : 0.9);
		var first = dark.get();
		put(first, Studio.environment(first));
	}

	static inline function key(dark:Bool):Int
		return dark ? 1 : 0;

	function put(scheme:Bool, e:Environment):Void {
		var made = [for (k => v in studios.get()) k => v];
		made.set(key(scheme), e);
		studios.set(made);
	}

	/** Builds the other scheme's studio on a worker, to have it when the scheme turns. **/
	public function prepareOther():Void {
		var other = !dark.get();
		ashui.core.Worker.run(() -> Studio.environment(other), e -> put(other, e));
	}

	function world(dark:Bool):World {
		var known = worlds.get(key(dark));
		if (known != null)
			return known;
		var sky = new Sky(dark);
		var ring = new Material({baseColor: primary, emissive: primary, emissiveStrength: 1.2, unlit: true, alpha: 0.55, alphaMode: Blend});
		var made:World = {
			floor: null,
			pool: null,
			rings: null,
			haze: sky.haze,
			fog: sky.fog,
			sky: sky.skybox,
			lights: [Directional(new Vec3(-0.35, -1, 0.3), 0xffffff, dark ? 2.2 : 1.6)],
			exposure: 1.0
		};
		var floorMaterial = new Material({baseColor: dark ? 0x4d5058 : 0xdadde4, roughness: 0.85});
		var poolMaterial = new Material({baseColor: primary, baseColorTexture: Glow.of(256), unlit: true, alpha: dark ? 0.65 : 0.5, alphaMode: Blend});
		var meshes = {
			floor: Geometry.plane(600, 600, 1, floorMaterial),
			pool: Geometry.plane(9.5, 9.5, 1, poolMaterial),
			rings: [Geometry.torus(2.95, 0.022, 160, 8, ring), Geometry.torus(3.18, 0.01, 160, 8, ring)]
		};
		made.floor = meshes.floor;
		made.pool = meshes.pool;
		made.rings = meshes.rings;
		worlds.set(key(dark), made);
		return made;
	}

	/** Draws the floor, the light under the car, the rings and the car, in the colour scheme's world. **/
	public function draw(ctx:DrawContext, spin = 0.0):Void {
		var w = world(dark.get());
		ctx.drawMesh(w.floor);
		ctx.drawMesh(w.pool, Mat4.translation(new Vec3(0, 0.002, 0)));
		for (ring in w.rings)
			ctx.drawMesh(ring, Mat4.translation(new Vec3(0, 0.004, 0)));
		car.draw(ctx, spin);
	}

	var flying:Null<Void->Bool> = null;

	/** Moves the camera to look from `azimuth` and `elevation` radians at `distance`, over `seconds`, easing out. **/
	public function look(azimuth:Float, elevation:Float, distance:Float, seconds = 0.7):Void {
		var a0 = camera.azimuth.get(), e0 = camera.elevation.get(), d0 = camera.distance.get();
		// By the short way round.
		var turn = azimuth - a0;
		turn = turn - Math.PI * 2 * Math.round(turn / (Math.PI * 2));
		var t = 0.0;
		var mine:Void->Bool = null;
		mine = () -> flying == mine;
		flying = mine;
		AnimationScheduler.main.addTicker(dt -> {
			if (flying != mine)
				return false;
			t += dt;
			var u = Math.min(1, t / seconds);
			var k = 1 - Math.pow(1 - u, 3);
			camera.azimuth.set(a0 + turn * k);
			camera.elevation.set(e0 + (elevation - e0) * k);
			camera.distance.set(d0 + (distance - d0) * k);
			if (u >= 1) {
				flying = null;
				return false;
			}
			true;
		});
	}
}
