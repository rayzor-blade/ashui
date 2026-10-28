package ashui.canvaskit;

import ashui.draw.DrawContext;
import ashui.draw3d.Light;
import ashui.draw3d.Scene3D;
import ashui.layout.Element;
import ashui.layout.IntoReactive;
import ashui.ui.Canvas;
import ashui.ui.Component;

typedef SceneKitProps = {
	/** Draws meshes and overlay shapes after the scene settings have been applied. **/
	?draw:DrawContext->Void,

	/** Orbit camera used by drag and scroll controls. Defaults to a new camera looking at the origin. **/
	?camera:OrbitCamera,

	?lights:IntoReactive<Array<Light>>,

	/** Ambient light color as `0xRRGGBB`. `ambientStrength` controls strength. **/
	?ambient:IntoReactive<Int>,

	?ambientStrength:IntoReactive<Float>,

	/** Exposure multiplier applied before tone mapping. **/
	?exposure:IntoReactive<Float>,

	/** Background color. `backgroundAlpha` controls opacity; defaults to transparent so the page shows through. **/
	?background:IntoReactive<Int>,

	?backgroundAlpha:IntoReactive<Float>,

	/** Environment lighting and reflections. Load an HDR sky with `Environment.fromHdr`. **/
	?environment:IntoReactive<Null<Environment>>,

	?environmentIntensity:IntoReactive<Float>,

	/** Backdrop for the scene, such as an environment or color sky. See `Skybox`. **/
	?skybox:IntoReactive<Null<Skybox>>,

	/** Distance haze applied to the scene and sky horizon. Defaults to none; see `Fog`. **/
	?fog:IntoReactive<ashui.draw3d.Fog>,

	/** Fish-eye distortion. Zero (default) disables it; 0.2–0.6 gives a wide-angle appearance. **/
	?lens:IntoReactive<Float>,

	/** Edge and corner darkening from zero (default, none) to one. **/
	?vignette:IntoReactive<Float>,

	/** Film grain from zero (default, none) to one. Can reduce visible banding in dark gradients. **/
	?grain:IntoReactive<Float>,

	/** Chromatic color fringes near the image edges, from zero (default, none) to one. **/
	?aberration:IntoReactive<Float>,

	/** Final image color grade. Defaults to none; see `ColorGrade`. **/
	?grade:IntoReactive<ashui.draw3d.ColorGrade>,

	/** Enables FXAA edge smoothing. Defaults to false. **/
	?antialias:IntoReactive<Bool>,

	/** Motion-blur shutter duration as a fraction of a frame, from zero (default, none) to one. **/
	?motionBlur:IntoReactive<Float>,

	/** Glow around bright parts of the scene. Defaults to none; see `Bloom`. **/
	?bloom:IntoReactive<ashui.draw3d.Bloom>,

	/** Enables shadows from the first light when it is directional. **/
	?shadows:IntoReactive<Bool>,

	/** Fraction of direct light blocked by shadows, from zero to one. Defaults to 0.7; ambient and environment light remain. **/
	?shadowStrength:IntoReactive<Float>,

	/**
		Shadow coverage radius around the camera target. Limit this for sharper
		shadows in wide scenes. Zero or omitted covers the whole scene.
	**/
	?shadowReach:IntoReactive<Float>,

	/** Ground grid beneath the scene, such as `GroundGrid.studio()`. **/
	?grid:IntoReactive<Null<GroundGrid>>,

	/**
		Renders continuously while true, for example with an animated `ScenePass`.
		Defaults to false, redrawing only when reactive inputs change.
	**/
	?animate:IntoReactive<Bool>,

	/** Enables camera drag and scroll controls. Defaults to true. **/
	?controls:Bool,

	/**
		Object selection model. Register bounds in `draw`, wrap selected meshes
		with `selection.draw`, and supply transform handlers for gizmos
		(c16e24c, 8ceba8d, 6a3a68b).
	**/
	?selection:Selection3D,

	/** Selected-object tool. Defaults to `Orbit`; accepts reactive values (6a3a68b). **/
	?gizmoMode:IntoReactive<GizmoMode>,

	/** Shows a world orientation widget in the top-right corner. Click an axis to look along it. **/
	?worldGizmo:Bool,

	/** World-widget right inset in layout units. Defaults to 16. **/
	?worldGizmoRight:Float,

	/** World-widget top inset in layout units. Defaults to 16. **/
	?worldGizmoTop:Float,

	/**
		Receives true while meshes wait for background texture compression,
		then false once all textures are ready. Meshes remain hidden until ready.
		Initialize to true to display loading UI from the first frame.
	**/
	?loading:ashui.reactive.Signal<Bool>,

	/**
		Receives rendered frames per second, updated once per second while
		rendering. Becomes zero one second after rendering stops.
	**/
	?fps:ashui.reactive.Signal<Float>,

	?id:String
}

/**
	An interactive 3D viewport with an `OrbitCamera`, lighting and `OrbitInput`
	controls. Size it like any other element:

	```haxe
	var camera = new OrbitCamera(0.4, 0.3, 3);
	<scene-kit camera={camera} lights={rig} width={960} height={720}
	    draw={ctx -> ctx.drawMesh(helmet)} />;
	```

	Signal props trigger redraws when their values change. The camera remains
	caller-owned, so application code can also call `camera.frame(...)` or
	`camera.reset()`.
**/
class SceneKit extends Component<SceneKitProps> {
	/** Editor gizmos, available when selection or the world widget is enabled. **/
	public var gizmos(default, null):Null<SceneGizmos>;

	/** Default directional key light from above and in front. **/
	static final defaultLights:Array<Light> = [Directional(new ashui.math.Vec3(-0.4, -1, -0.3), 0xffffff, 2.5)];

	function render():Element {
		var camera = props.camera != null ? props.camera : new OrbitCamera();
		// Drawn behind the meshes when `skybox` is set; its GPU parts freed with the element.
		var sky = new SkyboxPass();
		ashui.reactive.Owner.onCleanup(() -> sky.dispose());
		var loading = props.loading;
		if (props.selection != null)
			ashui.reactive.Owner.onCleanup(() -> props.selection.forgetRegions());
		gizmos = props.selection != null || props.worldGizmo == true ? new SceneGizmos(camera, props.selection, props.gizmoMode) : null;
		if (gizmos != null) {
			gizmos.world = props.worldGizmo == true;
			gizmos.cameraControls = props.controls != false;
			if (props.worldGizmoRight != null)
				gizmos.worldRight = props.worldGizmoRight;
			if (props.worldGizmoTop != null)
				gizmos.worldTop = props.worldGizmoTop;
		}
		var canvas = new Canvas({
			id: props.id,
			animate: props.animate,
			onLoading: loading != null ? v -> loading.set(v) : null,
			onSceneFrame: props.fps != null ? frameCounter(props.fps) : null,
			draw: ctx -> {
				var rig = new LightRig(read(props.lights, defaultLights), read(props.ambient, 0xffffff), read(props.ambientStrength, 0.25),
					read(props.environment, null), read(props.environmentIntensity, 1.0), read(props.shadows, false) ? {
						strength: read(props.shadowStrength, 0.7),
						reach: read(props.shadowReach, 0.0) > 0 ? read(props.shadowReach, 0.0) : null,
						focus: camera.target.get()
					} : null);
				ctx.setScene(new Scene3D(camera.camera(), rig, read(props.exposure, 1.0), read(props.background, 0x000000), read(props.backgroundAlpha, 0.0),
					read(props.fog, null), read(props.lens, 0.0), read(props.bloom, null), read(props.vignette, 0.0), read(props.grain, 0.0),
					read(props.aberration, 0.0), read(props.grade, null), read(props.antialias, false), read(props.motionBlur, 0.0)));
				sky.skybox = read(props.skybox, null);
				if (sky.skybox != null)
					ctx.drawPass(sky);
				var grid = read(props.grid, null);
				if (grid != null) {
					// One floor catches the shadows: a grounded sky's when there is one, the grid's otherwise.
					grid.catchesShadows = sky.skybox == null || !sky.skybox.match(Grounded(_, _, _, _, _, _));
					ctx.drawPass(grid);
				}
				if (props.selection != null)
					props.selection.begin(ctx);
				if (props.draw != null)
					props.draw(ctx);
				if (props.selection != null)
					props.selection.end(ctx);
				if (gizmos != null)
					gizmos.draw(ctx);
			}
		});
		if (gizmos != null)
			gizmos.attach(canvas.node);
		if (props.controls != false)
			new OrbitInput(camera).attach(canvas.node);
		return canvas;
	}

	/**
		Returns a frame callback that updates FPS each second and reports zero
		after a second without frames. Schedules only a timeout after the most
		recent frame, so no timer remains active while idle.
	**/
	static function frameCounter(fps:ashui.reactive.Signal<Float>):Void->Void {
		var frames = 0, since = -1.0, last = 0.0;
		var waiting = false;
		// Set after the frame: a signal set while painting would change what is being drawn.
		function report(v:Float)
			ashui.animation.AnimationScheduler.main.after(0, () -> fps.set(v));
		function idle() {
			var quiet = haxe.Timer.stamp() - last;
			if (quiet < 1) {
				ashui.animation.AnimationScheduler.main.after(1 - quiet, idle);
				return;
			}
			waiting = false;
			frames = 0;
			since = -1;
			report(0);
		}
		return () -> {
			var now = haxe.Timer.stamp();
			last = now;
			if (since < 0)
				since = now;
			frames++;
			if (now - since >= 1) {
				report(Math.round(frames / (now - since) * 10) / 10);
				frames = 0;
				since = now;
			}
			if (!waiting) {
				waiting = true;
				ashui.animation.AnimationScheduler.main.after(1, idle);
			}
		};
	}

	/** Reads a reactive prop or returns the fallback when omitted. **/
	static function read<T>(prop:Null<IntoReactive<T>>, fallback:T):T
		return prop == null ? fallback : switch (prop : ashui.layout.IntoReactive.ReactiveType<T>) {
			case Const(v): v;
			case Bound(s): s.get();
			case Derived(c): c.get();
		}
}
