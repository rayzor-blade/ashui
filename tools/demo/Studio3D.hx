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
	strength, the blue fill or none, the sky's strength and the exposure, 1
	unless given, with the grid
	shown or not. The nodes named in `hide` are not drawn. With `terrain`,
	the model stands on ground raised by that height map, or on endless
	procedural ground without one, made of the model's material or the
	first of the glTF at `rock`, repeated `tiles` times across by a texture
	transform. With `flight`, it takes off and flies on over the ground.
**/
typedef Example = {
	id:String,
	title:String,
	model:String,
	?sky:String,
	?makeSky:Void->Environment,
	?fog:ashui.draw3d.Fog,
	?shadowReach:Float,
	blur:Float,
	grounded:Bool,
	light:{key:Float, fill:Bool, sky:Float, ?exposure:Float, ?height:Float, ?from:Vec3, ?color:Int},
	grid:Bool,
	?hide:Array<String>,
	?terrain:{?heightMap:String, ?rock:String, tiles:Float},
	?flight:Bool
};

/** An example once chosen: its model and sky as the worker thread reads them, and what is made from them. **/
private class Loaded {
	public final model = Signal.make((null : Gltf));
	public final sky = Signal.make((null : Environment));
	public var pose:Null<GltfPose> = null;
	public var floor:Null<GroundGrid> = null;
	public var terrain:Null<ashui.draw3d.MeshData> = null;
	public var terrainAt:ashui.math.Mat4 = ashui.math.Mat4.IDENTITY;
	public var endless:Null<EndlessTerrain> = null;
	public var flight:Null<Flight> = null;
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
	Rogland's clear night sky; Blinc's Buster Drone (LaVADraGoN,
	CC-BY-4.0), read from Blinc's checkout beside this one, playing its clip
	in a photo studio's grey cove; Blinc's marble cliff (Amal Kumar, CC0),
	its rock repeated by glTF's KHR_texture_transform, standing on terrain
	its displacement map raises; and the drone taking off and flying on
	for ever over procedural ground of that rock, both under the night sky.
	The skies and the map are Poly Haven's, CC0.

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
			light: {key: 2.5, fill: true, sky: 1.5},
			grid: true
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
			grid: true,
			// The drone's own landing pad: the studio's floor takes its shadow instead.
			hide: ["Scheibe_Boden_0"]
		},
		{
			id: "terrain",
			title: "Marble cliff on terrain",
			model: "../../../../Blinc/examples/blinc_app_examples/examples/assets/3d/marble_cliff_02_2k.gltf/marble_cliff_02_2k.gltf",
			sky: ASSETS + "rogland_clear_night_2k.hdr",
			blur: 0,
			grounded: false,
			light: {key: 0.9, fill: true, sky: 1.2},
			grid: false,
			// The cliff's own displacement map raises the ground, made of the cliff's rock repeated across it.
			terrain: {heightMap: ASSETS + "marble_cliff_02_disp_1k.jpg", tiles: 8}
		},
		{
			id: "flight",
			title: "Drone over endless terrain",
			model: "../../../../Blinc/examples/blinc_app_examples/examples/assets/3d/buster_drone/scene.gltf",
			// Another world's night: its own sky, moonlight from over the camera's shoulder, fog where the ground ends.
			makeSky: AlienSky.make,
			fog: new ashui.draw3d.Fog(AlienSky.HAZE, 40, 135),
			// The ground is far too wide for one shadow map: it covers the drone's surroundings, sharply.
			shadowReach: 14,
			blur: 0,
			grounded: false,
			// Moonlight: weak and nearly white, no blue fill; the sky's own light the rest.
			light: {key: 1.5, fill: false, sky: 1.0, exposure: 0.85, height: AlienSky.LIGHT.y, from: AlienSky.LIGHT, color: 0xf2f0ea},
			grid: false,
			hide: ["Scheibe_Boden_0"],
			// Procedural ground of the marble cliff's rock, its texture repeated once a chunk.
			terrain: {rock: "../../../../Blinc/examples/blinc_app_examples/examples/assets/3d/marble_cliff_02_2k.gltf/marble_cliff_02_2k.gltf", tiles: 2},
			flight: true
		}
	];

	/**
		Ground for `m` to stand on: six times its size across, raised by the
		height map at `path` up to two fifths of its size, its base sunk under
		the model's, made of `material`.
	**/
	static function ground(m:Gltf, path:String, material:ashui.draw3d.Material):{mesh:ashui.draw3d.MeshData, at:ashui.math.Mat4} {
		var size = m.max.sub(m.min);
		var across = Math.max(size.x, size.z) * 6, rise = Math.max(size.x, Math.max(size.y, size.z)) * 0.4;
		var rock = material.with({doubleSided: false});
		var map = ashui.types.Bitmap.fromBytes(sys.io.File.getBytes(path));
		var mesh = ashui.canvaskit.Geometry.terrain(map, across, across, rise, 256, rock);
		map.dispose();
		return {mesh: mesh, at: ashui.math.Mat4.translation(new Vec3((m.min.x + m.max.x) / 2, m.min.y - rise * 0.45, (m.min.z + m.max.z) / 2))};
	}

	static function main() {
		// Those whose files are here: the drone needs Blinc's checkout.
		var examples = EXAMPLES.filter(e -> sys.FileSystem.exists(e.model) && (e.sky == null || sys.FileSystem.exists(e.sky)));
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
			ashui.core.Worker.run(() -> {
				var m = Gltf.load(e.model);
				var rock = e.terrain == null ? null : e.terrain.rock != null ? Gltf.load(e.terrain.rock).meshes[0].primitives[0].mesh.material : m.meshes[0].primitives[0].mesh.material;
				{model: m, rock: rock, terrain: e.terrain != null && e.terrain.heightMap != null ? ground(m, e.terrain.heightMap, rock) : null};
			}, made -> {
				var m = made.model;
				if (made.terrain != null) {
					l.terrain = made.terrain.mesh;
					l.terrainAt = made.terrain.at;
				}
				if (e.terrain != null && e.terrain.heightMap == null) {
					l.endless = new EndlessTerrain(made.rock.with({doubleSided: false}));
					l.endless.around(0, 0);
				}
				if (e.flight == true)
					l.flight = new Flight();
				l.pose = new GltfPose(m);
				if (e.hide != null)
					for (i in 0...m.nodes.length)
						if (e.hide.indexOf(m.nodes[i].name) >= 0)
							l.pose.visible[i] = false;
				l.floor = GroundGrid.studio(m.min.y);
				l.model.set(m);
			});
			ashui.core.Worker.run(() -> e.makeSky != null ? e.makeSky() : Environment.fromHdr(sys.io.File.getBytes(e.sky)), sky -> {
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
			camera.zoom(example.get().flight == true ? 1.4 : example.get().terrain != null ? 1.6 : m.animations.length > 0 ? 0.9 : 0.8);
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
			height.set(e.light.height != null ? e.light.height : 0.9);
			exposure.set(e.light.exposure != null ? e.light.exposure : 1.0);
		});
		var showGrid = Signal.make(true);
		new Watch(() -> example.get(), e -> showGrid.set(e.grid));
		// The terrain's texture transform, as KHR_texture_transform has it; off, every texture as it is, the cliff's own transform too.
		var transformOn = Signal.make(true);
		var tiles = Signal.make(8.0);
		var turn = Signal.make(0.0);
		var shiftU = Signal.make(0.0);
		var shiftV = Signal.make(0.0);
		new Watch(() -> example.get(), e -> if (e.terrain != null) tiles.set(e.terrain.tiles));
		var terrainTransform = Computed.make(() -> transformOn.get() ? new ashui.draw3d.TextureTransform(tiles.get(), tiles.get(),
			turn.get() * Math.PI / 180, shiftU.get(), shiftV.get()) : ashui.draw3d.TextureTransform.IDENTITY);
		var terrainMaterial = Computed.make(() -> {
			var t = current.get().terrain;
			t == null ? null : t.material.with({
				textureTransform: transformOn.get() ? new ashui.draw3d.TextureTransform(tiles.get(), tiles.get(), turn.get() * Math.PI / 180, shiftU.get(),
					shiftV.get()) : ashui.draw3d.TextureTransform.IDENTITY
			});
		});
		// Each material of the model without its texture transform, made once.
		var untransformed = new haxe.ds.ObjectMap<ashui.draw3d.Material, ashui.draw3d.Material>();
		function plain(m:ashui.draw3d.Material):ashui.draw3d.Material {
			var known = untransformed.get(m);
			if (known == null) {
				known = m.with({textureTransform: ashui.draw3d.TextureTransform.IDENTITY});
				untransformed.set(m, known);
			}
			return known;
		}
		var shadows = Signal.make(true);
		var shadowStrength = Signal.make(0.7);
		// True until the model's textures are in place: the viewport shows a spinner meanwhile.
		var loading = Signal.make(true);
		// The frames a second the scene is rendered at, shown in the corner.
		var fps = Signal.make(0.0);
		var rig = Computed.make(() -> {
			// From where the example says its light comes from, when it does; its height still the slider's.
			var from = example.get().light.from;
			var way = from != null ? new Vec3(-from.x, -height.get(), -from.z) : new Vec3(-0.4, -height.get(), -0.3);
			var color = example.get().light.color;
			var lights = [Directional(way, color != null ? color : 0xffffff, key.get())];
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
				var l = current.get(), f = l.flight;
				if (f != null) {
					f.advance(dt);
					clipTime.set(f.clipTime());
					l.endless.around(f.x, f.z);
					// The camera goes with the drone, turned and as far off as it was left.
					var m = model.get();
					camera.target.set(new Vec3(f.x, f.ground - m.min.y + (m.max.y - m.min.y) * 0.6, f.z));
				} else
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
		// In flight, the drone's controller held as the hover starts, so the clip's own turns and sways do not fight the way it flies.
		var held:Null<{node:Int, t:Vec3, r:ashui.math.Quat}> = null;
		function hold(l:Loaded, c:GltfAnimation) {
			if (held == null) {
				var node = -1;
				for (i in 0...l.pose.scene.nodes.length)
					if (l.pose.scene.nodes[i].name == "Drone_Controller")
						node = i;
				if (node < 0)
					return;
				var probe = new GltfPose(l.pose.scene);
				probe.play(c, Flight.HOVER);
				held = {node: node, t: probe.translations[node], r: probe.rotations[node]};
			}
			l.pose.translations[held.node] = held.t;
			l.pose.rotations[held.node] = held.r;
		}
		function draw(ctx:ashui.draw.DrawContext) {
			var m = model.get(), l = current.get();
			if (m == null)
				return;
			var c = clip.get();
			if (c != null)
				l.pose.play(c, Math.min(clipTime.get(), c.duration));
			if (l.terrain != null)
				ctx.drawMesh(l.terrain, l.terrainAt, terrainMaterial.get());
			if (l.endless != null)
				l.endless.draw(ctx, terrainTransform.get());
			var f = l.flight;
			if (f != null) {
				hold(l, c);
				var placed = ashui.math.Mat4.translation(new Vec3(f.x, f.ground - m.min.y, f.z))
					.mul(ashui.math.Mat4.rotation(ashui.math.Quat.axisAngle(Vec3.UP, f.heading)))
					.mul(ashui.math.Mat4.rotation(ashui.math.Quat.axisAngle(new Vec3(1, 0, 0), f.pitch())));
				l.pose.draw(ctx, placed, transformOn.get() ? null : plain);
			} else
				l.pose.draw(ctx, null, transformOn.get() ? null : plain);
		}

		var percent = (v:Float) -> Std.string(Math.round(v * 100)) + "%";
		function toggle(checked:Signal<Bool>, label:String):Element
			return <div flexDirection={Row} gap={10} alignItems={Center}><toggle-switch checked={checked} /><text>${label}</text></div>;
		function page():Element {
			// The select reads its options from its own children, so they are made here and spliced in.
			var choices:Array<Element> = [for (e in examples) <select-item value={e.id}>${e.title}</select-item>];
			return <div class="w-full h-full">
			<scene-kit widthPercent={1} heightPercent={1} loading={loading} fps={fps} fog={Computed.make(() -> example.get().fog)} shadowReach={Computed.make(() -> example.get().shadowReach != null ? (example.get().shadowReach : Float) : 0.0)} camera={camera} lights={rig} exposure={exposure} environment={sky} environmentIntensity={skyLight} shadows={shadows} shadowStrength={shadowStrength} grid={Computed.make(() -> showGrid.get() && model.get() != null ? current.get().floor : null)} skybox={skybox} draw={draw} />
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
					<accordion type="multiple" value={["animation", "texture", "lighting", "sky", "floor"]}>
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
						<accordion-item value="texture">
							<accordion-trigger>Texture transform</accordion-trigger>
							<accordion-content>
								<if {example.get().terrain != null}>
									<div flexDirection={Column} gap={14} paddingBottom={8}>
										{toggle(transformOn, "KHR_texture_transform")}
										<slider label="Tiles across" value={tiles} min={1} max={32} step={0.5} />
										<slider label="Rotation" value={turn} min={0} max={360} step={1} format={v -> '${Math.round(v)}°'} />
										<slider label="Offset u" value={shiftU} min={0} max={1} step={0.01} />
										<slider label="Offset v" value={shiftV} min={0} max={1} step={0.01} />
									</div>
								<else>
									<text class="text-text-secondary" paddingBottom={8}>${example.get().title} has no terrain to repeat a texture over.</text>
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

/**
	Ground without end, made as it is needed: square chunks round a point,
	`RANGE` each way, each built on the worker thread from `height`, and
	those that fall behind let go. Heights come from layers of smooth noise,
	the same for the same place every time, so chunks made apart meet. Each
	chunk's texture transform is moved by where the chunk is, so a texture
	repeated across them runs on without a seam whatever its rotation.
**/
private class EndlessTerrain {
	public static inline var CHUNK = 32.0;
	public static inline var RANGE = 4;
	public static inline var DIVISIONS = 48;

	/** Bumped as chunks come in or go: what draws the ground reads it. **/
	public final revision = Signal.make(0);

	final rock:ashui.draw3d.Material;
	final chunks = new Map<String, {mesh:ashui.draw3d.MeshData, cx:Int, cz:Int, ?made:{base:ashui.draw3d.TextureTransform, material:ashui.draw3d.Material}}>();
	final pending = new Map<String, Bool>();
	var centreX = 0x7fffffff;
	var centreZ = 0x7fffffff;

	public function new(rock:ashui.draw3d.Material)
		this.rock = rock;

	/** The ground's height at `x`, `z`: rolling hills, broken ground on them. **/
	public static function height(x:Float, z:Float):Float
		return 9 * fbm(x / 90, z / 90, 4) + 1.6 * fbm(x / 9 + 17, z / 9 - 5, 3);

	/** Makes the chunks round `x`, `z` and lets go of those further than a chunk past them. **/
	public function around(x:Float, z:Float):Void {
		var cx = Math.floor(x / CHUNK), cz = Math.floor(z / CHUNK);
		if (cx == centreX && cz == centreZ)
			return;
		centreX = cx;
		centreZ = cz;
		var changed = false;
		for (key => c in chunks)
			if (Std.int(Math.abs(c.cx - cx)) > RANGE + 1 || Std.int(Math.abs(c.cz - cz)) > RANGE + 1) {
				chunks.remove(key);
				changed = true;
			}
		for (dz in -RANGE...RANGE + 1)
			for (dx in -RANGE...RANGE + 1) {
				var x0 = cx + dx, z0 = cz + dz, key = '$x0,$z0';
				if (chunks.exists(key) || pending.exists(key))
					continue;
				pending.set(key, true);
				var material = rock;
				ashui.core.Worker.run(() -> ashui.canvaskit.Geometry.heightField(CHUNK, CHUNK, DIVISIONS,
					(i, j) -> height((x0 + i / DIVISIONS) * CHUNK, (z0 + j / DIVISIONS) * CHUNK), material), mesh -> {
						pending.remove(key);
						chunks.set(key, {mesh: mesh, cx: x0, cz: z0});
						revision.set(revision.get() + 1);
					});
			}
		if (changed)
			revision.set(revision.get() + 1);
	}

	/** Draws the chunks, each repeating the rock by `t` as though the ground were one piece. **/
	public function draw(ctx:ashui.draw.DrawContext, t:ashui.draw3d.TextureTransform):Void {
		revision.get();
		var m = t.matrix();
		for (c in chunks) {
			// The ring past the range is kept for coming back to, not drawn.
			if (Std.int(Math.abs(c.cx - centreX)) > RANGE || Std.int(Math.abs(c.cz - centreZ)) > RANGE)
				continue;
			// The chunk's corner, in chunks, carried through the transform: its texture starts where its neighbour's ends.
			// Made again only as `t` changes, so a chunk keeps its material, and its GPU binding, from frame to frame.
			if (c.made == null || c.made.base != t) {
				var offset = new ashui.draw3d.TextureTransform(t.scaleX, t.scaleY, t.rotation, t.offsetX + m.a * c.cx + m.b * c.cz,
					t.offsetY + m.c * c.cx + m.d * c.cz);
				c.made = {base: t, material: c.mesh.material.with({textureTransform: offset})};
			}
			ctx.drawMesh(c.mesh, ashui.math.Mat4.translation(new Vec3((c.cx + 0.5) * CHUNK, 0, (c.cz + 0.5) * CHUNK)), c.made.material);
		}
	}

	/** `octaves` of value noise, each half the size and half the height of the last, about -1 to 1. **/
	static function fbm(x:Float, z:Float, octaves:Int):Float {
		var sum = 0.0, amplitude = 0.5, frequency = 1.0;
		for (_ in 0...octaves) {
			sum += amplitude * noise(x * frequency, z * frequency);
			amplitude *= 0.5;
			frequency *= 2.03;
		}
		return sum;
	}

	/** Smooth noise -1 to 1: a random value at each whole point, eased between them. **/
	static function noise(x:Float, z:Float):Float {
		var ix = Math.floor(x), iz = Math.floor(z);
		var fx = x - ix, fz = z - iz;
		var ux = fx * fx * (3 - 2 * fx), uz = fz * fz * (3 - 2 * fz);
		var a = hash(ix, iz), b = hash(ix + 1, iz), c = hash(ix, iz + 1), d = hash(ix + 1, iz + 1);
		return (a + (b - a) * ux) + ((c + (d - c) * ux) - (a + (b - a) * ux)) * uz;
	}

	/** A value -1 to 1 for the whole point `x`, `z`, the same every time. **/
	static function hash(x:Int, z:Int):Float {
		var h = x * 374761393 + z * 668265263;
		h = (h ^ (h >>> 13)) * 1274126177;
		h = h ^ (h >>> 16);
		return (h & 0xffff) / 32767.5 - 1;
	}
}

/**
	The drone's flight: it takes off where it stands, playing its clip from
	`LIFT` to `HOVER`, then flies on for ever, looping the clip's hover
	from `HOVER` to `HOVER_END`, along a slowly winding way, keeping its
	height over the ground ahead. Its controller node is held as it is at
	`HOVER`, so the clip's own turns do not fight the way it flies.
**/
private class Flight {
	public static inline var LIFT = 5.0;
	public static inline var HOVER = 19.2;
	public static inline var HOVER_END = 24.4;
	public static inline var SPEED = 9.0;

	public var x = 0.0;
	public var z = 0.0;
	public var heading = 0.0;
	public var ground:Float;
	public var elapsed = 0.0;
	public var travelled = 0.0;

	public function new()
		ground = EndlessTerrain.height(0, 0);

	/** Moves it on `dt` seconds. **/
	public function advance(dt:Float):Void {
		elapsed += dt;
		var flying = elapsed - (HOVER - LIFT - 4);
		// Up to speed over four seconds as the take-off ends.
		var speed = flying <= 0 ? 0 : SPEED * Math.min(1, flying / 4);
		travelled += speed * dt;
		heading = 0.6 * Math.sin(travelled / 70);
		x += Math.sin(heading) * speed * dt;
		z += Math.cos(heading) * speed * dt;
		// The highest ground a little way ahead, followed smoothly, so it rises before a hill.
		var ahead = -1e9;
		for (k in 0...4) {
			var d = k * 4;
			ahead = Math.max(ahead, EndlessTerrain.height(x + Math.sin(heading) * d, z + Math.cos(heading) * d));
		}
		if (speed > 0)
			ground += (ahead - ground) * Math.min(1, dt * 1.5);
	}

	/** Where its clip is: the take-off once, then the hover over and over. **/
	public function clipTime():Float
		return elapsed < HOVER - LIFT ? LIFT + elapsed : HOVER + (elapsed - (HOVER - LIFT)) % (HOVER_END - HOVER);

	/** How far it leans into its way, by its speed. **/
	public function pitch():Float {
		var flying = elapsed - (HOVER - LIFT - 4);
		return flying <= 0 ? 0 : 0.18 * Math.min(1, flying / 4);
	}
}

/**
	The night sky of another world: MozillaHubs' Milky Way panorama
	(CC-BY-NC-SA-4.0) and a faint haze round the horizon, `HAZE`, which the
	scene's fog matches, so the ground's far edge melts into it.
**/
private class AlienSky {
	public static inline var PANORAMA = "../../snapshot/assets/3d/sky_pano_-_milkyway/textures/lambert1_emissive.jpeg";

	/**
		Where the moonlight comes from: over the camera's shoulder, as a film
		lights a night shot, so what the camera sees of the drone is lit.
	**/
	public static final LIGHT = new Vec3(0.5, 0.55, 0.65).normalize();

	/** The horizon's colour, `0xRRGGBB`, for the fog. **/
	public static inline var HAZE = 0x10141c;

	static inline var WIDTH = 2048;
	static inline var HEIGHT = 1024;

	public static function make():Environment {
		var image = ashui.types.Bitmap.fromBytes(sys.io.File.getBytes(PANORAMA));
		var px = image.pixels(WIDTH, HEIGHT);
		image.dispose();
		// sRGB to linear, once for each byte value.
		var linear = [for (b in 0...256) Math.pow(b / 255, 2.2)];
		return Environment.fromFunction(512, d -> radiance(d, px, linear));
	}

	static function radiance(d:Vec3, px:haxe.io.Bytes, linear:Array<Float>):Vec3 {
		// The panorama as an HDR sky is laid round: across by the way round, down by the angle from overhead.
		var u = 0.5 + Math.atan2(d.x, -d.z) / (2 * Math.PI);
		var v = Math.acos(Math.max(-1, Math.min(1, d.y))) / Math.PI;
		var x = Std.int(u * WIDTH) % WIDTH, y = Std.int(Math.min(HEIGHT - 1, v * HEIGHT));
		var o = (y * WIDTH + x) * 4;
		var c = new Vec3(linear[px.get(o)], linear[px.get(o + 1)], linear[px.get(o + 2)]).scale(1.6);
		// Haze thickening toward the horizon; below it, the ground's darkness.
		var haze = new Vec3(0.0055, 0.0075, 0.012);
		var low = 1 - Math.min(1, Math.abs(d.y) * 5);
		c = c.lerp(haze, low * 0.85);
		if (d.y < 0)
			c = c.scale(Math.max(0, 1 + d.y * 4));
		return c;
	}
}
