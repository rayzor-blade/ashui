import ashui.app.WindowConfig;
import ashui.app.WindowedApp;
import ashui.canvaskit.Gltf;
import ashui.canvaskit.OrbitCamera;
import ashui.canvaskit.SceneKit;
import ashui.components.Button;
import ashui.components.Card;
import ashui.components.Slider;
import ashui.components.Spinner;
import ashui.components.ToggleSwitch;
import ashui.draw3d.Light;
import ashui.canvaskit.GroundGrid;
import ashui.draw3d.Skybox;
import ashui.layout.Element;
import ashui.math.Vec3;
import ashui.reactive.Computed;
import ashui.reactive.Signal;
import ashui.theme.themes.DefaultTheme;
import ashui.types.Style;

/**
	A 3D studio: Khronos' DamagedHelmet (CC BY-NC, theblueturtle_) in a
	`<scene-kit>`, lit by and reflecting Rogland's clear night sky (Poly
	Haven, CC0), beside a panel that sets the exposure, the key light's
	strength and height and the sky's, shows the sky behind it, sharp or
	blurred, and a studio grid under it, turns the fill light on and off, and puts the camera back. Drag to turn round the helmet,
	Shift-drag or right-drag to move across, scroll to come nearer.

		tools/demo/run.sh Studio3D.hx
**/
class Studio3D {
	static function main() {
		var helmet = Gltf.load("../../snapshot/assets/3d/DamagedHelmet/DamagedHelmet.gltf");
		// The sky is built on the worker thread; the helmet is lit by ambient light until it comes.
		var night = Signal.make((null : ashui.draw3d.Environment));
		var started = haxe.Timer.stamp();
		var hdr = sys.io.File.getBytes("../../snapshot/assets/3d/rogland_clear_night_2k.hdr");
		ashui.core.Worker.run(() -> ashui.draw3d.Environment.fromHdr(hdr), sky -> {
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
		// The helmet stands on the grid: the grid at the bottom of its box.
		var floor = GroundGrid.studio(helmet.min.y);
		// True until the helmet's textures are in place: the viewport shows a spinner meanwhile.
		var loading = Signal.make(true);
		var rig = Computed.make(() -> {
			var lights = [Directional(new Vec3(-0.4, -height.get(), -0.3), 0xffffff, key.get())];
			if (fill.get())
				lights.push(Directional(new Vec3(0.6, 0.2, -0.8), 0x8899ff, 0.8));
			lights;
		});
		var percent = (v:Float) -> Std.string(Math.round(v * 100)) + "%";
		function page():Element return <div flexDirection={Row} width={1100} height={720} padding={16} gap={16}>
			<div width={760} height={688}>
				<scene-kit loading={loading} camera={camera} lights={rig} exposure={exposure} environment={night} environmentIntensity={skyLight} grid={Computed.make(() -> showGrid.get() ? floor : null)} skybox={Computed.make(() -> showSky.get() && night.get() != null ? Sky(night.get(), blur.get(), skyLight.get()) : null)} draw={ctx -> helmet.draw(ctx)} width={760} height={688} />
				<if {loading.get()}>
					<div position={Absolute} left={0} top={0} width={760} height={688} flexDirection={Column} gap={12} alignItems={Center} justifyContent={Justify.Center}>
						<spinner />
						<text>Loading the helmet</text>
					</div>
				</if>
			</div>
			<card width={292}>
				<card-header><card-title>Studio</card-title><card-description>Drag to turn, Shift-drag to move, scroll to zoom</card-description></card-header>
				<card-content>
					<div flexDirection={Column} gap={18}>
						<slider label="Exposure" value={exposure} min={0.2} max={3} step={0.05} />
						<slider label="Key light" value={key} min={0} max={6} step={0.1} />
						<slider label="Key height" value={height} min={0.1} max={2} step={0.05} />
						<slider label="Sky light" value={skyLight} min={0} max={4} step={0.05} format={percent} />
						<slider label="Sky blur" value={blur} min={0} max={1} step={0.05} format={percent} />
						<div flexDirection={Row} gap={10} alignItems={Center}><toggle-switch checked={showSky} /><text>Show the sky</text></div>
						<div flexDirection={Row} gap={10} alignItems={Center}><toggle-switch checked={showGrid} /><text>Show the grid</text></div>
						<div flexDirection={Row} gap={10} alignItems={Center}><toggle-switch checked={fill} /><text>Blue fill light</text></div>
						<button variant={Outline} onClick={_ -> camera.reset()}>Reset camera</button>
					</div>
				</card-content>
			</card>
		</div>;
		WindowedApp.run(new WindowConfig().title("3D studio").size(1100, 720).theme(DefaultTheme.bundle()), page);
	}
}
