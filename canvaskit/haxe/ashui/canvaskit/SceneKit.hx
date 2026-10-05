package ashui.canvaskit;

import ashui.draw.DrawContext;
import ashui.draw3d.Light;
import ashui.draw3d.Scene3D;
import ashui.layout.Element;
import ashui.layout.IntoReactive;
import ashui.ui.Canvas;
import ashui.ui.Component;

typedef SceneKitProps = {
	/** Draws the scene's meshes, then any shapes over them; the scene is set before it is called. **/
	?draw:DrawContext->Void,

	/** The camera, moved by dragging and scrolling; a new one, looking at the origin, by default. **/
	?camera:OrbitCamera,

	?lights:IntoReactive<Array<Light>>,

	/** The light that reaches everywhere, `0xRRGGBB`, and how strong. **/
	?ambient:IntoReactive<Int>,

	?ambientStrength:IntoReactive<Float>,

	/** What lit colours are multiplied by before tone mapping. **/
	?exposure:IntoReactive<Float>,

	/** What is behind the scene, and how opaque; by default nothing, so the page shows through. **/
	?background:IntoReactive<Int>,

	?backgroundAlpha:IntoReactive<Float>,

	/** Light from all round, and what surfaces reflect: a sky, from an `.hdr` with `Environment.fromHdr`. **/
	?environment:IntoReactive<Null<Environment>>,

	?environmentIntensity:IntoReactive<Float>,

	/** What is drawn behind the scene: an environment, blurred or not, or colours (see `Skybox`). **/
	?skybox:IntoReactive<Null<Skybox>>,

	/** Haze that the scene, and its sky's horizon, fade into with distance (see `Fog`). There is none by default. **/
	?fog:IntoReactive<ashui.draw3d.Fog>,

	/** How strongly the scene is bent by a fish-eye lens. 0, the default, means no lens; 0.2 to 0.6 resembles a wide-angle lens. **/
	?lens:IntoReactive<Float>,

	/** How much the scene's edges and corners are darkened, from 0 (the default, none) to 1. **/
	?vignette:IntoReactive<Float>,

	/** Film grain, from 0 (the default, none) to 1 (heavy). It hides banding in dark gradients. **/
	?grain:IntoReactive<Float>,

	/** Chromatic aberration: colour fringes towards the edges, from 0 (the default, none) to 1 (strong). **/
	?aberration:IntoReactive<Float>,

	/** A colour grade for the final image (see `ColorGrade`); none by default. **/
	?grade:IntoReactive<ashui.draw3d.ColorGrade>,

	/** Whether edges are smoothed by FXAA anti-aliasing; off by default. **/
	?antialias:IntoReactive<Bool>,

	/** Motion blur: how long the shutter stays open, as a share of a frame, from 0 (the default, none) to 1. **/
	?motionBlur:IntoReactive<Float>,

	/** Bloom: bright parts of the scene glow onto their surroundings (see `Bloom`). There is none by default. **/
	?bloom:IntoReactive<ashui.draw3d.Bloom>,

	/** Whether the first light, if directional, casts shadows. **/
	?shadows:IntoReactive<Bool>,

	/** How much of the first light its shadows keep off, 0 to 1; 0.7 by default. The rest of the light, ambient and sky, still reaches into them. **/
	?shadowStrength:IntoReactive<Float>,

	/**
		How far around the camera's target shadows are cast. Use it for a
		scene too wide for one shadow map to cover sharply. By default, or at
		0, shadows cover the whole scene.
	**/
	?shadowReach:IntoReactive<Float>,

	/** A ground grid under the scene, `GroundGrid.studio()` or one's own (see `GroundGrid`). **/
	?grid:IntoReactive<Null<GroundGrid>>,

	/**
		True for a scene drawn anew every frame, as one with a pass that
		animates (an `animated` `ScenePass`) needs: the canvas asks for every
		frame. False by default: it is drawn as what it reads changes.
	**/
	?animate:IntoReactive<Bool>,

	/** Whether dragging and scrolling move the camera; true by default. **/
	?controls:Bool,

	/**
		Set to true while meshes it draws wait for their textures, which are
		compressed in the background, and to false when all are in place: show
		a loading state while it is true. A mesh is not drawn until its
		textures are, so none shows plain. Start it at true to show the
		loading state from the first frame.
	**/
	?loading:ashui.reactive.Signal<Bool>,

	/**
		Set to the frames a second the scene is rendered at, once a second
		while it renders; 0 a second after it stops, as it does when nothing
		in it moves or changes.
	**/
	?fps:ashui.reactive.Signal<Float>,

	?id:String
}

/**
	A 3D viewport, `<scene-kit>`: a canvas that draws a scene through an
	`OrbitCamera`, lit by `lights`, moved by `OrbitInput` as it is
	dragged and scrolled. Size it as any element:

	```haxe
	var camera = new OrbitCamera(0.4, 0.3, 3);
	<scene-kit camera={camera} lights={rig} width={960} height={720}
		draw={ctx -> ctx.drawMesh(helmet)} />;
	```

	Each prop given as a signal is followed: the canvas draws again when
	the camera or a prop it reads changes, and only then. The camera is
	the caller's to keep, so other code can move it (`camera.frame(...)`,
	`camera.reset()`).
**/
class SceneKit extends Component<SceneKitProps> {
	/** A key light from above and in front, as a scene has with no `lights`. **/
	static final defaultLights:Array<Light> = [Directional(new ashui.math.Vec3(-0.4, -1, -0.3), 0xffffff, 2.5)];

	function render():Element {
		var camera = props.camera != null ? props.camera : new OrbitCamera();
		// Drawn behind the meshes when `skybox` is set; its GPU parts freed with the element.
		var sky = new SkyboxPass();
		ashui.reactive.Owner.onCleanup(() -> sky.dispose());
		var loading = props.loading;
		var canvas = new Canvas({
			id: props.id,
			animate: props.animate,
			onLoading: loading != null ? v -> loading.set(v) : null,
			onSceneFrame: props.fps != null ? frameCounter(props.fps) : null,
			draw: ctx -> {
				var rig = new LightRig(read(props.lights, defaultLights), read(props.ambient, 0xffffff), read(props.ambientStrength, 0.25),
					read(props.environment, null), read(props.environmentIntensity, 1.0), read(props.shadows, false) ? {strength: read(props.shadowStrength, 0.7), reach: read(props.shadowReach, 0.0) > 0 ? read(props.shadowReach, 0.0) : null, focus: camera.target.get()} : null);
				ctx.setScene(new Scene3D(camera.camera(), rig, read(props.exposure, 1.0), read(props.background, 0x000000), read(props.backgroundAlpha, 0.0),
					read(props.fog, null), read(props.lens, 0.0), read(props.bloom, null),
					read(props.vignette, 0.0), read(props.grain, 0.0), read(props.aberration, 0.0),
					read(props.grade, null), read(props.antialias, false),
					read(props.motionBlur, 0.0)));
				sky.skybox = read(props.skybox, null);
				if (sky.skybox != null)
					ctx.drawPass(sky);
				var grid = read(props.grid, null);
				if (grid != null) {
					// One floor catches the shadows: a grounded sky's when there is one, the grid's otherwise.
					grid.catchesShadows = sky.skybox == null || !sky.skybox.match(Grounded(_, _, _, _, _, _));
					ctx.drawPass(grid);
				}
				if (props.draw != null)
					props.draw(ctx);
			}
		});
		if (props.controls != false)
			new OrbitInput(camera).attach(canvas.node);
		return canvas;
	}

	/**
		Counts frames into `fps`: the rate over each second they come in, set
		as the second ends, and 0 once a second goes by with none. Only a
		timer waiting on the last frame runs, so an idle scene costs nothing.
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

	/** A prop's value now, followed when it is a signal or computed; `fallback` when it is not given. **/
	static function read<T>(prop:Null<IntoReactive<T>>, fallback:T):T
		return prop == null ? fallback : switch (prop : ashui.layout.IntoReactive.ReactiveType<T>) {
			case Const(v): v;
			case Bound(s): s.get();
			case Derived(c): c.get();
		}
}
