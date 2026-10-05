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
	?environment:IntoReactive<Null<ashui.draw3d.Environment>>,

	?environmentIntensity:IntoReactive<Float>,

	/** What is drawn behind the scene: an environment, blurred or not, or colours (see `Skybox`). **/
	?skybox:IntoReactive<Null<ashui.draw3d.Skybox>>,

	/** A ground grid under the scene, `GroundGrid.studio()` or one's own (see `GroundGrid`). **/
	?grid:IntoReactive<Null<ashui.draw3d.GroundGrid>>,

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
	function render():Element {
		var camera = props.camera != null ? props.camera : new OrbitCamera();
		var base = Scene3D.DEFAULT;
		var loading = props.loading;
		var canvas = new Canvas({
			id: props.id,
			onLoading: loading != null ? v -> loading.set(v) : null,
			draw: ctx -> {
				ctx.setScene(new Scene3D(camera.camera(), read(props.lights, base.lights), read(props.ambient, base.ambient),
					read(props.ambientStrength, base.ambientStrength), read(props.exposure, base.exposure), read(props.background, base.background),
					read(props.backgroundAlpha, base.backgroundAlpha), read(props.environment, null), read(props.environmentIntensity, 1.0),
					read(props.skybox, null), read(props.grid, null)));
				if (props.draw != null)
					props.draw(ctx);
			}
		});
		if (props.controls != false)
			new OrbitInput(camera).attach(canvas.node);
		return canvas;
	}

	/** A prop's value now, followed when it is a signal or computed; `fallback` when it is not given. **/
	static function read<T>(prop:Null<IntoReactive<T>>, fallback:T):T
		return prop == null ? fallback : switch (prop : ashui.layout.IntoReactive.ReactiveType<T>) {
			case Const(v): v;
			case Bound(s): s.get();
			case Derived(c): c.get();
		}
}
