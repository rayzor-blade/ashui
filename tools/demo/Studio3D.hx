import ashui.app.WindowConfig;
import ashui.app.WindowedApp;
import ashui.canvaskit.Environment;
import ashui.canvaskit.Gltf;
import ashui.canvaskit.GltfAnimation;
import ashui.canvaskit.GltfPose;
import ashui.canvaskit.GroundGrid;
import ashui.canvaskit.OrbitCamera;
import ashui.canvaskit.SceneKit;
import ashui.canvaskit.Skybox;
import ashui.components.Accordion;
import ashui.components.Button;
import ashui.components.Card;
import ashui.components.ScrollArea;
import ashui.components.Select;
import ashui.components.Slider;
import ashui.components.Spinner;
import ashui.components.ToggleSwitch;
import ashui.draw3d.Light;
import ashui.layout.Element;
import ashui.math.Vec3;
import ashui.reactive.Computed;
import ashui.reactive.Signal;
import ashui.reactive.Watch;
import ashui.theme.themes.DefaultTheme;
import ashui.types.Style;

/**
	One of the studio's examples: a glTF model and the HDR sky it stands
	under, blurred by `blur` to begin with; `grounded` for a sky whose floor
	is laid under the model. It starts lit as `light` says: the key light's
	strength, the blue fill or none, and the sky's strength. The nodes named
	in `hide` are not drawn.
**/
typedef Example = {
	id:String,
	title:String,
	model:String,
	sky:String,
	blur:Float,
	grounded:Bool,
	light:{key:Float, fill:Bool, sky:Float},
	?hide:Array<String>
};

/** An example once chosen: its model and sky as the worker thread reads them, and what is made from them. **/
private class Loaded {
	public final model = Signal.make((null : Gltf));
	public final sky = Signal.make((null : Environment));
	public var pose:Null<GltfPose> = null;
	public var floor:Null<GroundGrid> = null;
	public var started = false;

	public function new() {}
}

/**
	A 3D studio: a `<scene-kit>` filling the window, and a frosted panel
	over it. The panel chooses an example, each a glTF model under its own
	HDR sky, which lights it and shows behind it, sharp or blurred, its
	floor laid under the model where the sky has one, with a studio grid
	under it catching its shadow. Its sections, each opening and
	closing, play the model's animation and scrub it, and set the lighting,
	the sky, and the floor and shadows; a corner shows the frames a second
	the scene renders at. Drag to turn round the model,
	Shift-drag or right-drag to move across, scroll to come nearer.

	The examples: Khronos' DamagedHelmet (CC BY-NC, theblueturtle_) under
	Rogland's clear night sky, and Blinc's Buster Drone (LaVADraGoN,
	CC-BY-4.0), read from Blinc's checkout beside this one, playing its clip
	in a photo studio's grey cove; both skies Poly Haven's, CC0.

		tools/demo/run.sh Studio3D.hx
**/
class Studio3D {
	static final ASSETS = "../../snapshot/assets/3d/";

	static final EXAMPLES:Array<Example> = [
		{
			id: "helmet",
			title: "Damaged helmet",
			model: ASSETS + "DamagedHelmet/DamagedHelmet.gltf",
			sky: ASSETS + "rogland_clear_night_2k.hdr",
			blur: 0.35,
			grounded: false,
			light: {key: 2.5, fill: true, sky: 1.5}
		},
		{
			id: "drone",
			title: "Buster drone, animated",
			model: "../../../../Blinc/examples/blinc_app_examples/examples/assets/3d/buster_drone/scene.gltf",
			sky: ASSETS + "studio_small_08_2k.hdr",
			blur: 0,
			grounded: true,
			// Lit by the studio's softboxes as its floor is, so the drone's landing pad looks laid on it.
			light: {key: 2.5, fill: false, sky: 1.0},
			// The drone's own landing pad: the studio's floor takes its shadow instead.
			hide: ["Scheibe_Boden_0"]
		}
	];

	static function main() {
		// Those whose files are here: the drone needs Blinc's checkout.
		var examples = EXAMPLES.filter(e -> sys.FileSystem.exists(e.model) && sys.FileSystem.exists(e.sky));
		var loaded = [for (e in examples) e.id => new Loaded()];
		var chosen = Signal.make(examples[0].id);
		var example = Computed.make(() -> examples.filter(e -> e.id == chosen.get())[0]);
		var current = Computed.make(() -> loaded.get(chosen.get()));
		// An example's model and sky are read on the worker thread the first time it is chosen.
		new Watch(() -> chosen.get(), id -> {
			var l = loaded.get(id), e = examples.filter(e -> e.id == id)[0];
			if (l.started)
				return;
			l.started = true;
			var started = haxe.Timer.stamp();
			ashui.core.Worker.run(() -> Gltf.load(e.model), m -> {
				l.pose = new GltfPose(m);
				if (e.hide != null)
					for (i in 0...m.nodes.length)
						if (e.hide.indexOf(m.nodes[i].name) >= 0)
							l.pose.visible[i] = false;
				l.floor = GroundGrid.studio(m.min.y);
				l.model.set(m);
			});
			ashui.core.Worker.run(() -> Environment.fromHdr(sys.io.File.getBytes(e.sky)), sky -> {
				trace('${e.id}: model and sky in ${Math.round((haxe.Timer.stamp() - started) * 1000)}ms, off the main thread');
				l.sky.set(sky);
			});
		});
		var model = Computed.make(() -> current.get().model.get());
		var sky = Computed.make(() -> current.get().sky.get());
		var clip = Computed.make(() -> {
			var m = model.get();
			m != null && m.animations.length > 0 ? m.animations[0] : (null : GltfAnimation);
		});

		var camera = new OrbitCamera(0.4, 0.15, 3, null, 0.7);
		// Framed afresh as each model comes in.
		new Watch(() -> model.get(), m -> if (m != null) {
			camera.frame(m.min, m.max);
			camera.zoom(m.animations.length > 0 ? 0.9 : 0.8);
		});
		var exposure = Signal.make(1.0);
		var key = Signal.make(2.5);
		var height = Signal.make(0.9);
		var skyLight = Signal.make(1.5);
		var showSky = Signal.make(true);
		var blur = Signal.make(0.35);
		// A grounded sky's camera height over the floor and the floor's reach, in the model's units, from its size as it comes in.
		var groundHeight = Signal.make(1.0);
		var groundRadius = Signal.make(10.0);
		new Watch(() -> model.get(), m -> if (m != null) {
			var size = m.max.sub(m.min);
			trace('${example.get().id}: ${Math.round(size.x * 100) / 100} by ${Math.round(size.y * 100) / 100} by ${Math.round(size.z * 100) / 100}');
			groundHeight.set(size.y * 1.5);
			groundRadius.set(size.y * 1.5 * 3);
		});
		var fill = Signal.make(true);
		// Each example starts with its own sky blur and lighting.
		new Watch(() -> example.get(), e -> {
			blur.set(e.blur);
			key.set(e.light.key);
			fill.set(e.light.fill);
			skyLight.set(e.light.sky);
		});
		var showGrid = Signal.make(true);
		var shadows = Signal.make(true);
		var shadowStrength = Signal.make(0.7);
		// True until the model's textures are in place: the viewport shows a spinner meanwhile.
		var loading = Signal.make(true);
		// The frames a second the scene is rendered at, shown in the corner.
		var fps = Signal.make(0.0);
		var rig = Computed.make(() -> {
			var lights = [Directional(new Vec3(-0.4, -height.get(), -0.3), 0xffffff, key.get())];
			if (fill.get())
				lights.push(Directional(new Vec3(0.6, 0.2, -0.8), 0x8899ff, 0.8));
			lights;
		});

		// The clip, played on the demo's own clock: it ticks while the clip plays, once the model and its textures are in, and stops with it.
		var playing = Signal.make(true);
		var clipTime = Signal.make(0.0);
		var ticking = false;
		new Watch(() -> clip.get(), _ -> clipTime.set(0));
		new Watch(() -> clip.get() != null && playing.get() && !loading.get(), run -> if (run && !ticking) {
			ticking = true;
			ashui.animation.AnimationScheduler.main.addTicker(dt -> {
				var c = clip.get();
				if (c == null || !playing.get() || loading.get())
					return ticking = false;
				clipTime.set((clipTime.get() + dt) % c.duration);
				return true;
			});
		});
		var skybox = Computed.make(() -> {
			var e = sky.get(), m = model.get();
			if (!showSky.get() || e == null)
				(null : Skybox);
			else if (example.get().grounded && m != null)
				Grounded(e, groundHeight.get(), groundRadius.get(), m.min.y, blur.get(), skyLight.get());
			else
				Sky(e, blur.get(), skyLight.get());
		});
		function draw(ctx:ashui.draw.DrawContext) {
			var m = model.get(), l = current.get();
			if (m == null)
				return;
			var c = clip.get();
			if (c != null)
				l.pose.play(c, Math.min(clipTime.get(), c.duration));
			l.pose.draw(ctx);
		}

		var percent = (v:Float) -> Std.string(Math.round(v * 100)) + "%";
		function toggle(checked:Signal<Bool>, label:String):Element
			return <div flexDirection={Row} gap={10} alignItems={Center}><toggle-switch checked={checked} /><text>${label}</text></div>;
		function page():Element {
			// The select reads its options from its own children, so they are made here and spliced in.
			var choices:Array<Element> = [for (e in examples) <select-item value={e.id}>${e.title}</select-item>];
			return <div class="w-full h-full">
			<scene-kit widthPercent={1} heightPercent={1} loading={loading} fps={fps} camera={camera} lights={rig} exposure={exposure} environment={sky} environmentIntensity={skyLight} shadows={shadows} shadowStrength={shadowStrength} grid={Computed.make(() -> showGrid.get() && model.get() != null ? current.get().floor : null)} skybox={skybox} draw={draw} />
			<if {loading.get() || model.get() == null}>
				<div class="w-full h-full" position={Absolute} left={0} top={0} flexDirection={Column} alignItems={Center} justifyContent={Justify.Center}>
					<div class="flex flex-col items-center gap-3 px-5 py-4 rounded-xl border border-white/10 bg-surface/70 backdrop-blur-md">
						<spinner />
						<text>Loading ${example.get().title}</text>
					</div>
				</div>
			</if>
			<div class="px-3 py-1.5 rounded-lg border border-white/10 bg-surface/70 backdrop-blur-md" position={Absolute} left={16} bottom={16}>
				<text class="text-xs font-medium">${fps.get() > 0 ? Math.round(fps.get()) + " fps" : "idle"}</text>
			</div>
			<div class="flex flex-col gap-4 p-5 rounded-xl border border-white/10 bg-surface/70 backdrop-blur-md" position={Absolute} top={16} right={16} bottom={16} width={300}>
				<card-header><card-title>Studio</card-title><card-description>Drag to turn, Shift-drag to move, scroll to zoom</card-description></card-header>
				<select value={chosen} widthPercent={1}>{choices}</select>
				<scroll-area flexGrow={1} flexBasis={0} minHeight={0}>
					<accordion type="multiple" value={["animation", "lighting", "sky", "floor"]}>
						<accordion-item value="animation">
							<accordion-trigger>Animation</accordion-trigger>
							<accordion-content>
								<if {clip.get() != null}>
									<div flexDirection={Column} gap={14} paddingBottom={8}>
										<slider label={'Clip "${clip.get().name}"'} value={clipTime} min={0} max={clip.get().duration} step={0.01} format={v -> '${Math.round(v * 10) / 10}s'} />
										{toggle(playing, "Play")}
									</div>
								<else>
									<text class="text-text-secondary" paddingBottom={8}>${example.get().title} has no animation.</text>
								</if>
							</accordion-content>
						</accordion-item>
						<accordion-item value="lighting">
							<accordion-trigger>Lighting</accordion-trigger>
							<accordion-content>
								<div flexDirection={Column} gap={14} paddingBottom={8}>
									<slider label="Exposure" value={exposure} min={0.2} max={3} step={0.05} />
									<slider label="Key light" value={key} min={0} max={6} step={0.1} />
									<slider label="Key height" value={height} min={0.1} max={2} step={0.05} />
									{toggle(fill, "Blue fill light")}
								</div>
							</accordion-content>
						</accordion-item>
						<accordion-item value="sky">
							<accordion-trigger>Sky</accordion-trigger>
							<accordion-content>
								<div flexDirection={Column} gap={14} paddingBottom={8}>
									<slider label="Sky light" value={skyLight} min={0} max={4} step={0.05} format={percent} />
									<slider label="Sky blur" value={blur} min={0} max={1} step={0.05} format={percent} />
									{toggle(showSky, "Show the sky")}
									<if {example.get().grounded && model.get() != null}>
										<div flexDirection={Column} gap={14}>
											<slider label="Ground height" value={groundHeight} min={0} max={(model.get().max.y - model.get().min.y) * 6} step={0.01} />
											<slider label="Ground radius" value={groundRadius} min={1} max={Math.max(model.get().max.x - model.get().min.x, model.get().max.z - model.get().min.z) * 40} step={0.1} />
										</div>
									</if>
								</div>
							</accordion-content>
						</accordion-item>
						<accordion-item value="floor">
							<accordion-trigger>Floor and shadows</accordion-trigger>
							<accordion-content>
								<div flexDirection={Column} gap={14} paddingBottom={8}>
									{toggle(showGrid, "Show the grid")}
									{toggle(shadows, "Shadows")}
									<slider label="Shadow strength" value={shadowStrength} min={0} max={1} step={0.05} format={percent} />
								</div>
							</accordion-content>
						</accordion-item>
					</accordion>
				</scroll-area>
				<button variant={Outline} onClick={_ -> camera.reset()}>Reset camera</button>
			</div>
		</div>;
		}
		WindowedApp.run(new WindowConfig().title("3D studio").size(1200, 820).theme(DefaultTheme.bundle()), page);
	}
}
