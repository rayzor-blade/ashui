import ashui.app.WindowConfig;
import ashui.app.WindowedApp;
import ashui.canvaskit.Gltf;
import ashui.canvaskit.GltfPose;
import ashui.canvaskit.OrbitCamera;
import ashui.canvaskit.SceneKit;
import ashui.components.Button;
import ashui.components.Card;
import ashui.components.Slider;
import ashui.components.Spinner;
import ashui.components.Tabs;
import ashui.components.ToggleSwitch;
import ashui.draw3d.Light;
import ashui.canvaskit.GroundGrid;
import ashui.canvaskit.Skybox;
import ashui.canvaskit.Environment;
import ashui.layout.Element;
import ashui.math.Vec3;
import ashui.reactive.Computed;
import ashui.reactive.Signal;
import ashui.reactive.Watch;
import ashui.theme.themes.DefaultTheme;
import ashui.types.Style;

/**
	A 3D studio: Khronos' DamagedHelmet (CC BY-NC, theblueturtle_), or
	Blinc's Buster Drone (LaVADraGoN, CC-BY-4.0) playing its clip, in a
	`<scene-kit>`, lit by and reflecting Rogland's clear night sky (Poly
	Haven, CC0), filling the window. A frosted panel floats over it that
	sets the exposure, the key light's strength and height and the sky's,
	shows the sky behind, sharp or blurred, a studio grid under the helmet
	and the shadow it casts there, sets how much of the key light the
	shadow keeps off, turns the fill light on and off, and puts the camera
	back. Drag to turn round the helmet, Shift-drag or
	right-drag to move across, scroll to come nearer.

		tools/demo/run.sh Studio3D.hx
**/
class Studio3D {
	/** Blinc's Buster Drone, from Blinc's checkout beside this one. **/
	static final DRONE = "../../../../Blinc/examples/blinc_app_examples/examples/assets/3d/buster_drone/scene.gltf";

	static function main() {
		var helmet = Gltf.load("../../snapshot/assets/3d/DamagedHelmet/DamagedHelmet.gltf");
		// The drone is read on the worker thread, and offered once it is in.
		var drone = Signal.make((null : Gltf));
		var dronePose:Null<GltfPose> = null;
		var droneFloor:Null<GroundGrid> = null;
		if (sys.FileSystem.exists(DRONE))
			ashui.core.Worker.run(() -> Gltf.load(DRONE), d -> {
				dronePose = new GltfPose(d);
				droneFloor = GroundGrid.studio(d.min.y);
				drone.set(d);
			});
		var model = Signal.make("helmet");
		var showDrone = Computed.make(() -> model.get() == "drone" && drone.get() != null);
		// The sky is built on the worker thread; the helmet is lit by ambient light until it comes.
		var night = Signal.make((null : Environment));
		var started = haxe.Timer.stamp();
		var hdr = sys.io.File.getBytes("../../snapshot/assets/3d/rogland_clear_night_2k.hdr");
		ashui.core.Worker.run(() -> Environment.fromHdr(hdr), sky -> {
			trace('sky made in ${Math.round((haxe.Timer.stamp() - started) * 1000)}ms, off the main thread');
			night.set(sky);
		});
		var camera = new OrbitCamera(0.4, 0.15, 3, null, 0.7);
		camera.frame(helmet.min, helmet.max);
		camera.zoom(0.8);
		var exposure = Signal.make(1.0);
		var key = Signal.make(2.5);
		var height = Signal.make(0.9);
		var skyLight = Signal.make(1.5);
		var showSky = Signal.make(true);
		var blur = Signal.make(0.35);
		var fill = Signal.make(true);
		var showGrid = Signal.make(true);
		var shadows = Signal.make(true);
		var shadowStrength = Signal.make(0.7);
		// The helmet stands on the grid: the grid at the bottom of its box.
		var floor = GroundGrid.studio(helmet.min.y);
		// The drone's clip, played on the demo's own clock: it ticks while the clip plays and stops with it.
		var playing = Signal.make(true);
		var clipTime = Signal.make(0.0);
		var ticking = false;
		new Watch(() -> showDrone.get() && playing.get(), run -> if (run && !ticking) {
			ticking = true;
			ashui.animation.AnimationScheduler.main.addTicker(dt -> {
				if (!showDrone.get() || !playing.get())
					return ticking = false;
				clipTime.set((clipTime.get() + dt) % drone.get().animations[0].duration);
				return true;
			});
		});
		// Framed afresh as the model changes.
		new Watch(() -> showDrone.get(), d -> {
			var m = d ? drone.get() : helmet;
			camera.frame(m.min, m.max);
			camera.zoom(d ? 0.9 : 0.8);
		});
		function draw(ctx:ashui.draw.DrawContext)
			if (showDrone.get()) {
				dronePose.play(drone.get().animations[0], clipTime.get());
				dronePose.draw(ctx);
			} else
				helmet.draw(ctx);
		// True until the helmet's textures are in place: the viewport shows a spinner meanwhile.
		var loading = Signal.make(true);
		var rig = Computed.make(() -> {
			var lights = [Directional(new Vec3(-0.4, -height.get(), -0.3), 0xffffff, key.get())];
			if (fill.get())
				lights.push(Directional(new Vec3(0.6, 0.2, -0.8), 0x8899ff, 0.8));
			lights;
		});
		var percent = (v:Float) -> Std.string(Math.round(v * 100)) + "%";
		function page():Element return <div class="w-full h-full">
			<scene-kit widthPercent={1} heightPercent={1} loading={loading} camera={camera} lights={rig} exposure={exposure} environment={night} environmentIntensity={skyLight} shadows={shadows} shadowStrength={shadowStrength} grid={Computed.make(() -> showGrid.get() ? (showDrone.get() ? droneFloor : floor) : null)} skybox={Computed.make(() -> showSky.get() && night.get() != null ? Sky(night.get(), blur.get(), skyLight.get()) : null)} draw={draw} />
			<if {loading.get()}>
				<div class="w-full h-full" position={Absolute} left={0} top={0} flexDirection={Column} gap={12} alignItems={Center} justifyContent={Justify.Center}>
					<spinner />
					<text>Loading the model</text>
				</div>
			</if>
			<div class="flex flex-col gap-4 p-5 rounded-xl border border-white/10 bg-surface/70 backdrop-blur-md" position={Absolute} top={16} right={16} width={292}>
				<card-header><card-title>Studio</card-title><card-description>Drag to turn, Shift-drag to move, scroll to zoom</card-description></card-header>
				<tabs value={model}>
					<tabs-list><tabs-trigger value="helmet">Helmet</tabs-trigger><tabs-trigger value="drone">${drone.get() != null ? "Drone" : "Drone (loading)"}</tabs-trigger></tabs-list>
				</tabs>
				<if {showDrone.get()}>
					<div flexDirection={Column} gap={14}>
						<slider label="Clip time" value={clipTime} min={0} max={drone.get().animations[0].duration} step={0.01} format={v -> '${Math.round(v * 10) / 10}s'} />
						<div flexDirection={Row} gap={10} alignItems={Center}><toggle-switch checked={playing} /><text>Play "${drone.get().animations[0].name}"</text></div>
					</div>
				</if>
				<div flexDirection={Column} gap={14}>
					<slider label="Exposure" value={exposure} min={0.2} max={3} step={0.05} />
					<slider label="Key light" value={key} min={0} max={6} step={0.1} />
					<slider label="Key height" value={height} min={0.1} max={2} step={0.05} />
					<slider label="Sky light" value={skyLight} min={0} max={4} step={0.05} format={percent} />
					<slider label="Sky blur" value={blur} min={0} max={1} step={0.05} format={percent} />
					<slider label="Shadow strength" value={shadowStrength} min={0} max={1} step={0.05} format={percent} />
					<div flexDirection={Row} gap={10} alignItems={Center}><toggle-switch checked={showSky} /><text>Show the sky</text></div>
					<div flexDirection={Row} gap={10} alignItems={Center}><toggle-switch checked={showGrid} /><text>Show the grid</text></div>
					<div flexDirection={Row} gap={10} alignItems={Center}><toggle-switch checked={shadows} /><text>Shadows</text></div>
					<div flexDirection={Row} gap={10} alignItems={Center}><toggle-switch checked={fill} /><text>Blue fill light</text></div>
					<button variant={Outline} onClick={_ -> camera.reset()}>Reset camera</button>
				</div>
			</div>
		</div>;
		WindowedApp.run(new WindowConfig().title("3D studio").size(1200, 820).theme(DefaultTheme.bundle()), page);
	}
}
