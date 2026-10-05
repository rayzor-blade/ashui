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
	under.

	- `blur` is the sky's starting blur. `grounded` projects the sky's floor
	  under the model. `panorama` is an image shown as the visible sky.
	- `light` sets the starting key light strength, whether the blue fill is
	  on, the sky light's strength, and the exposure (1 if not given).
	- `grid` says whether the studio grid starts shown.
	- Nodes named in `hide` are not drawn.
	- With `terrain`, the model stands on ground. Given a `heightMap`, the
	  ground is raised by it; without one, it is endless procedural ground.
	  The ground uses the model's material, or the first material of the
	  glTF at `rock`, repeated `tiles` times across by a texture transform.
	- With `flight`, the model takes off and flies over the ground.
**/
typedef Example = {
	id:String,
	title:String,
	model:String,
	?sky:String,
	?makeSky:Void->Environment,
	?panorama:String,
	?lens:Float,
	?view:{azimuth:Float, elevation:Float, distance:Float, fov:Float, offset:Array<Float>},
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

/** The loaded state of an example: its model and sky, which the worker thread reads, and what the studio builds from them. **/
private class Loaded {
	public final model = Signal.make((null : Gltf));
	public final sky = Signal.make((null : Environment));
	public var pose:Null<GltfPose> = null;
	public var floor:Null<GroundGrid> = null;
	public var terrain:Null<ashui.draw3d.MeshData> = null;
	public var terrainAt:ashui.math.Mat4 = ashui.math.Mat4.IDENTITY;
	public var endless:Null<EndlessTerrain> = null;
	public var flight:Null<Flight> = null;
	/** The example's panorama, once read. **/
	public final panorama = Signal.make((null : ashui.types.Bitmap));
	public var started = false;

	public function new() {}
}

/**
	A 3D studio: a `<scene-kit>` fills the window, with a frosted control
	panel floating over it. The panel chooses an example; each is a glTF
	model under its own sky, which lights the model and shows behind it.
	Collapsible sections play and scrub the model's animation and adjust the
	lighting, post-processing, sky, floor and shadows. A corner shows how
	many frames a second the scene renders. Drag to orbit the model,
	Shift-drag or right-drag to pan, and scroll to zoom.

	The examples:
	- Khronos' DamagedHelmet (CC BY-NC, theblueturtle_) under Rogland's
	  clear night sky.
	- Blinc's Buster Drone (LaVADraGoN, CC-BY-4.0), read from Blinc's
	  checkout beside this one, playing its animation in a photo studio.
	- Blinc's marble cliff (Amal Kumar, CC0), its rock repeated with glTF's
	  KHR_texture_transform, standing on terrain raised by its displacement
	  map.
	- The drone taking off and flying endlessly over procedural ground made
	  of that rock, under MozillaHubs' Milky Way panorama.
	The HDR skies and the displacement map come from Poly Haven (CC0).

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
			// The sky sphere's picture, shown as it is and as the sphere lays it round; the sky made from it lights the scene.
			panorama: AlienSky.PANORAMA,
			// Far ground fades into the haze toward the horizon.
			// Whole before the curve's horizon, a few hundred units out, so the far ground ends in haze, not an edge.
			// Seen through: the curved horizon and far ridges show faintly in it.
			fog: new ashui.draw3d.Fog(AlienSky.HAZE, 40, 420, 0.7),
			// The ground is far too wide for one shadow map: it covers the drone's surroundings, sharply.
			shadowReach: 14,
			blur: 0,
			grounded: false,
			// Moonlight: weak and nearly white, no blue fill; the sky's own light the rest.
			light: {key: 1.4, fill: false, sky: 1.0, exposure: 1.3, height: AlienSky.LIGHT.y, from: AlienSky.LIGHT, color: 0xf4f0e8},
			grid: false,
			hide: ["Scheibe_Boden_0"],
			// Procedural ground of the marble cliff's rock, its texture repeated once a chunk.
			terrain: {rock: "../../../../Blinc/examples/blinc_app_examples/examples/assets/3d/marble_cliff_02_2k.gltf/marble_cliff_02_2k.gltf", tiles: 3},
			flight: true,
			lens: 0.2
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
		var chosen = Signal.make(examples[examples.length - 1].id);
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
					l.endless = new EndlessTerrain(made.rock.with({doubleSided: false, shader: CurvedGround.WGSL}));
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
			if (e.panorama != null)
				ashui.core.Worker.run(() -> ashui.types.Bitmap.fromBytes(sys.io.File.getBytes(e.panorama)), image -> {
					// Its pixels are freed once its texture is on the GPU.
					image.gpuOnly = true;
					l.panorama.set(image);
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
		// The drone's heading the chase camera last turned to, where it last put the camera's target,
		// and that target's offset from the drone in the drone's own frame: right, up, ahead. A pan moves the offset.
		var chased = 0.0;
		var chaseTarget:Null<Vec3> = null;
		var chaseOffset = new Vec3(0, 0, 0);
		inline function turnedBy(v:Vec3, heading:Float)
			return new Vec3(v.x * Math.cos(heading) + v.z * Math.sin(heading), v.y, -v.x * Math.sin(heading) + v.z * Math.cos(heading));
		// Framed afresh as each model comes in.
		new Watch(() -> model.get(), m -> if (m != null) {
			// A panorama looks like a sky through a wide lens; through a narrow one its picture is magnified past its resolution.
			camera.fovY.set(example.get().panorama != null ? 1.2 : 0.7);
			// In flight the camera starts behind the drone, a little to its right, looking the way it goes.
			if (example.get().flight == true) {
				var v = example.get().view;
				// Beside the drone, a little behind, looking at its flank.
				camera.azimuth.set(v != null ? v.azimuth : Math.PI / 2 + 0.25);
				if (v != null) {
					camera.elevation.set(v.elevation);
					camera.distance.set(v.distance);
					camera.fovY.set(v.fov);
				}
				chaseOffset = v != null ? new Vec3(v.offset[0], v.offset[1], v.offset[2]) : new Vec3(0, 0, 0);
				chaseTarget = null;
				chased = 0;
			}
			camera.frame(m.min, m.max);
			camera.zoom(example.get().flight == true ? 0.85 : example.get().terrain != null ? 1.6 : m.animations.length > 0 ? 0.9 : 0.8);
		});
		var exposure = Signal.make(1.0);
		var key = Signal.make(2.5);
		var height = Signal.make(0.9);
		var skyLight = Signal.make(1.5);
		var showSky = Signal.make(true);
		var blur = Signal.make(0.35);
		// How far across the sky's sphere the camera sits, from its centre (0) to almost its wall (1):
		// further out, the far wall is further off, its stars smaller, and orbiting shows more depth.
		var skyDepth = Signal.make(0.85);
		// The fish-eye's bend, 0 none.
		var lens = Signal.make(0.0);
		// How strongly bright parts glow, and from how bright.
		// As modern engines default to: a low threshold and a gentle strength, so everything glows in proportion to its brightness.
		// How much the edges darken.
		var vignette = Signal.make(0.45);
		// Film grain and colour fringing, both subtle.
		var grain = Signal.make(0.35);
		var aberration = Signal.make(0.3);
		// Smoothed edges, and how much of the night colour grade.
		var antialias = Signal.make(true);
		var gradeStrength = Signal.make(0.5);
		// The shutter, as a share of a frame: spinning rotors blur into discs.
		var motionBlur = Signal.make(0.5);
		var bloomStrength = Signal.make(0.3);
		var bloomThreshold = Signal.make(0.2);
		new Watch(() -> example.get(), e -> lens.set(e.lens != null ? (e.lens : Float) : 0.0));
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
		// Where the clip is; in flight, ticking with it.
		var clipTime = Signal.make(0.0);
		// How far the key light is turned round the vertical from where the example puts it, in degrees.
		var lightAngle = Signal.make(0.0);
		new Watch(() -> example.get(), _ -> lightAngle.set(0));
		var rig = Computed.make(() -> {
			// The key light comes from where the example says, or from the front left by default, turned round the
			// vertical by the Key angle slider. Its height is the Key height slider's.
			// In flight it also turns with the drone, as the chase camera does, so the side the camera sees stays lit.
			var from = example.get().light.from;
			if (from == null)
				from = new Vec3(0.4, 0, 0.3);
			var angle = lightAngle.get() * Math.PI / 180;
			clipTime.get();
			var f = current.get().flight;
			if (f != null)
				angle += f.heading;
			from = new Vec3(from.x * Math.cos(angle) + from.z * Math.sin(angle), 0, -from.x * Math.sin(angle) + from.z * Math.cos(angle));
			var way = new Vec3(-from.x, -height.get(), -from.z);
			var color = example.get().light.color;
			var lights = [Directional(way, color != null ? color : 0xffffff, key.get())];
			if (fill.get())
				lights.push(Directional(new Vec3(0.6, 0.2, -0.8), 0x8899ff, 0.8));
			lights;
		});

		// The clip, played on the demo's own clock: it ticks while the clip plays, once the model and its textures are in, and stops with it.
		var playing = Signal.make(true);
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
					var anchor = new Vec3(f.x, f.ground + f.climb - m.min.y + (m.max.y - m.min.y) * 0.6, f.z);
					// Panned since the last tick: the pan becomes the offset, kept as the drone flies on.
					if (chaseTarget != null && camera.target.get().distance(chaseTarget) > 1e-6)
						chaseOffset = turnedBy(camera.target.get().sub(chaseTarget.sub(turnedBy(chaseOffset, chased))), -chased);
					chaseTarget = anchor.add(turnedBy(chaseOffset, f.heading));
					camera.target.set(chaseTarget);
					// A chase camera: turned as the drone turns, on top of whatever turn a drag gave it.
					camera.azimuth.set(camera.azimuth.get() + f.heading - chased);
					chased = f.heading;
				} else
					clipTime.set((clipTime.get() + dt) % c.duration);
				return true;
			});
		});
		var skybox = Computed.make(() -> {
			var e = sky.get(), m = model.get();
			if (!showSky.get() || e == null)
				(null : Skybox);
			else if (current.get().panorama.get() != null)
				// As the sky sphere lays its picture: upside down, turned a little over a quarter of the way round.
				// On a sphere round the drone, the camera within it: orbiting, its near wall slides past its far one.
				Panorama(current.get().panorama.get(), {
					turn: AlienSky.TURN,
					upsideDown: true,
					centre: camera.target.get(),
					radius: camera.distance.get() / skyDepth.get()
				});
			else if (example.get().grounded && m != null)
				Grounded(e, groundHeight.get(), groundRadius.get(), m.min.y, blur.get(), skyLight.get());
			else
				Sky(e, blur.get(), skyLight.get());
		});
		// In flight, the drone's controller held as the hover starts, so the clip's own turns and sways do not fight the way it flies.
		var held:Null<{node:Int, t:Vec3, r:ashui.math.Quat, yaw:Float}> = null;
		function hold(l:Loaded, c:GltfAnimation) {
			if (held == null) {
				var node = -1;
				for (i in 0...l.pose.scene.nodes.length)
					if (l.pose.scene.nodes[i].name == "Drone_Controller")
						node = i;
				if (node < 0)
					return;
				var probe = new GltfPose(l.pose.scene);
				probe.play(c, Flight.LIFT);
				var before = probe.world()[node];
				probe.play(c, Flight.HOVER);
				var after = probe.world()[node];
				// How far round the clip has turned the drone by the hover: the way its side points, then and at take-off.
				inline function way(m:ashui.math.Mat4)
					return Math.atan2(m.get(0, 0), m.get(0, 2));
				held = {node: node, t: probe.translations[node], r: probe.rotations[node], yaw: way(after) - way(before)};
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
				// Turned back by the clip's own turn, so it faces its way once the hover starts, and flies nose first.
				var placed = ashui.math.Mat4.translation(new Vec3(f.x, f.ground + f.climb - m.min.y, f.z))
					.mul(ashui.math.Mat4.rotation(ashui.math.Quat.axisAngle(Vec3.UP, f.heading - (held != null ? held.yaw : 0))))
					.mul(ashui.math.Mat4.rotation(ashui.math.Quat.axisAngle(new Vec3(1, 0, 0), f.pitch())));
				l.pose.draw(ctx, placed, transformOn.get() ? null : plain);
			} else
				l.pose.draw(ctx, null, transformOn.get() ? null : plain);
		}

		var percent = (v:Float) -> Std.string(Math.round(v * 100)) + "%";
		function toggle(checked:Signal<Bool>, label:String):Element
			return <div flexDirection={Row} gap={10} alignItems={Center}><toggle-switch checked={checked} /><text>${label}</text></div>;
		// The camera and light as they are, written to the terminal as an example's settings: the camera relative to the drone in flight.
		function printView() {
			var f = current.get().flight;
			var r = (v:Float) -> Math.round(v * 1000) / 1000;
			var azimuth = f != null ? camera.azimuth.get() - f.heading : camera.azimuth.get();
			Sys.println('view: {azimuth: ${r(azimuth)}, elevation: ${r(camera.elevation.get())}, distance: ${r(camera.distance.get())}, fov: ${r(camera.fovY.get())}, '
				+ 'offset: [${r(chaseOffset.x)}, ${r(chaseOffset.y)}, ${r(chaseOffset.z)}]},');
			Sys.println('light: {key: ${r(key.get())}, fill: ${fill.get()}, sky: ${r(skyLight.get())}, exposure: ${r(exposure.get())}, height: ${r(height.get())}, angle: ${r(lightAngle.get())}}, '
				+ 'shadowStrength: ${r(shadowStrength.get())}, tiles: ${r(tiles.get())}, turn: ${r(turn.get())}');
		}
		function page():Element {
			// The select reads its options from its own children, so they are made here and spliced in.
			var choices:Array<Element> = [for (e in examples) <select-item value={e.id}>${e.title}</select-item>];
			return <div class="w-full h-full">
			<scene-kit widthPercent={1} heightPercent={1} loading={loading} fps={fps} lens={lens} vignette={vignette} grain={grain} aberration={aberration} antialias={antialias} motionBlur={motionBlur} grade={Computed.make(() -> gradeStrength.get() > 0 ? ashui.draw3d.ColorGrade.NIGHT.at(gradeStrength.get()) : null)} bloom={Computed.make(() -> new ashui.draw3d.Bloom(bloomStrength.get(), bloomThreshold.get()))} fog={Computed.make(() -> example.get().fog)} shadowReach={Computed.make(() -> example.get().shadowReach != null ? (example.get().shadowReach : Float) : 0.0)} camera={camera} lights={rig} exposure={exposure} environment={sky} environmentIntensity={skyLight} shadows={shadows} shadowStrength={shadowStrength} grid={Computed.make(() -> showGrid.get() && model.get() != null ? current.get().floor : null)} skybox={skybox} draw={draw} />
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
									<slider label="Fish-eye" value={lens} min={0} max={1} step={0.01} format={percent} />
									<slider label="Vignette" value={vignette} min={0} max={1} step={0.01} format={percent} />
									<slider label="Film grain" value={grain} min={0} max={1} step={0.01} format={percent} />
									<slider label="Chromatic aberration" value={aberration} min={0} max={1} step={0.01} format={percent} />
									<slider label="Night colour grade" value={gradeStrength} min={0} max={1} step={0.01} format={percent} />
									<slider label="Motion blur" value={motionBlur} min={0} max={1} step={0.01} format={percent} />
									{toggle(antialias, "Anti-aliasing (FXAA)")}
									<slider label="Bloom" value={bloomStrength} min={0} max={2} step={0.05} format={percent} />
									<slider label="Bloom threshold" value={bloomThreshold} min={0} max={3} step={0.05} />
									<slider label="Key light" value={key} min={0} max={6} step={0.1} />
									<slider label="Key angle" value={lightAngle} min={-180} max={180} step={1} format={v -> '${Math.round(v)}°'} />
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
									<if {example.get().panorama != null}>
										<slider label="Sky depth" value={skyDepth} min={0} max={0.97} step={0.01} format={v -> '${Math.round(v * 100)}%'} />
									</if>
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
				<div flexDirection={Row} gap={8}>
					<button variant={Outline} flexGrow={1} onClick={_ -> camera.reset()}>Reset camera</button>
					<button variant={Outline} flexGrow={1} onClick={_ -> printView()}>Print view</button>
				</div>
			</div>
		</div>;
		}
		WindowedApp.run(new WindowConfig().title("3D studio").size(1200, 820).theme(DefaultTheme.bundle()), page);
	}
}

/**
	Endless ground, built as it is needed out to the horizon. It is made of
	rings of square chunks around a point. Each ring's chunks are four
	times as wide as the previous ring's and more coarsely divided, so
	nearby ground is detailed and distant ground is cheap.

	Each chunk is built on the worker thread from `height`, and chunks left
	behind are released. Heights come from layers of smooth noise that give
	the same value for the same place every time, so separately built
	chunks meet exactly. The outer rings skip the finest noise layer, which
	they are too coarse to show, and sit slightly lower so that the inner
	ring covers them where they overlap. Each chunk's texture transform is
	offset and scaled by its position and size, so the rock continues
	without a seam across chunks and rings.
**/
private class EndlessTerrain {
	/** The rings, nearest first: their chunks' width, divisions each way, how many chunks out each way, and how far below. **/
	static final RINGS:Array<{chunk:Float, divisions:Int, range:Int, drop:Float}> = [
		{chunk: 32, divisions: 48, range: 3, drop: 0},
		{chunk: 128, divisions: 32, range: 3, drop: 0.5},
		{chunk: 512, divisions: 24, range: 3, drop: 2.0}
	];

	/** Bumped as chunks come in or go: what draws the ground reads it. **/
	public final revision = Signal.make(0);

	final rock:ashui.draw3d.Material;
	final chunks = new Map<String, {mesh:ashui.draw3d.MeshData, ring:Int, cx:Int, cz:Int, ?made:{base:ashui.draw3d.TextureTransform, material:ashui.draw3d.Material}}>();
	final pending = new Map<String, Bool>();
	final centreX = [for (_ in RINGS) 0x7fffffff];
	final centreZ = [for (_ in RINGS) 0x7fffffff];

	public function new(rock:ashui.draw3d.Material)
		this.rock = rock;

	/**
		The ground's height at `x`, `z`: ridged mountains far apart, rolling
		hills, and broken ground on them unless `fine` is false.
	**/
	public static function height(x:Float, z:Float, fine = true):Float {
		var ridge = 1 - Math.abs(fbm(x / 1400 + 41, z / 1400 - 13, 3) * 2);
		var h = 110 * ridge * ridge * ridge - 30 + 22 * fbm(x / 160, z / 160, 4);
		return fine ? h + 1.6 * fbm(x / 9 + 17, z / 9 - 5, 3) : h;
	}

	/** Makes the chunks of every ring round `x`, `z` and lets go of those further than a chunk past them. **/
	public function around(x:Float, z:Float):Void {
		var changed = false;
		for (r in 0...RINGS.length) {
			var ring = RINGS[r];
			var cx = Math.floor(x / ring.chunk), cz = Math.floor(z / ring.chunk);
			if (cx == centreX[r] && cz == centreZ[r])
				continue;
			centreX[r] = cx;
			centreZ[r] = cz;
			for (key => c in chunks)
				if (c.ring == r && (Std.int(Math.abs(c.cx - cx)) > ring.range + 1 || Std.int(Math.abs(c.cz - cz)) > ring.range + 1)) {
					chunks.remove(key);
					changed = true;
				}
			for (dz in -ring.range...ring.range + 1)
				for (dx in -ring.range...ring.range + 1) {
					var x0 = cx + dx, z0 = cz + dz, key = '$r:$x0,$z0';
					if (chunks.exists(key) || pending.exists(key) || inside(r, x0, z0))
						continue;
					pending.set(key, true);
					var material = rock, size = ring.chunk, d = ring.divisions, fine = r == 0;
					ashui.core.Worker.run(() -> ashui.canvaskit.Geometry.heightField(size, size, d,
						(i, j) -> height((x0 + i / d) * size, (z0 + j / d) * size, fine), material), mesh -> {
							pending.remove(key);
							chunks.set(key, {mesh: mesh, ring: r, cx: x0, cz: z0});
							revision.set(revision.get() + 1);
						});
				}
		}
		if (changed)
			revision.set(revision.get() + 1);
	}

	/** Whether chunk `cx`, `cz` of ring `r` lies wholly within the ground the ring inside it draws. **/
	function inside(r:Int, cx:Int, cz:Int):Bool {
		if (r == 0)
			return false;
		var inner = RINGS[r - 1], size = RINGS[r].chunk;
		var lo = (centreX[r - 1] - inner.range) * inner.chunk, hi = (centreX[r - 1] + inner.range + 1) * inner.chunk;
		var loZ = (centreZ[r - 1] - inner.range) * inner.chunk, hiZ = (centreZ[r - 1] + inner.range + 1) * inner.chunk;
		return cx * size >= lo && (cx + 1) * size <= hi && cz * size >= loZ && (cz + 1) * size <= hiZ;
	}

	/** Draws the chunks, each repeating the rock by `t` as though the ground were one piece, `t`'s scale being the rock's repeats a nearest chunk. **/
	public function draw(ctx:ashui.draw.DrawContext, t:ashui.draw3d.TextureTransform):Void {
		revision.get();
		var m = t.matrix();
		for (c in chunks) {
			var ring = RINGS[c.ring];
			// The ring past the range is kept for coming back to, not drawn; nor what the ring inside covers.
			if (Std.int(Math.abs(c.cx - centreX[c.ring])) > ring.range || Std.int(Math.abs(c.cz - centreZ[c.ring])) > ring.range
				|| inside(c.ring, c.cx, c.cz))
				continue;
			// The chunk's corner, in nearest chunks, carried through the transform, and its texture as many times wider as
			// the chunk is: its texture starts where its neighbour's ends, at the same size in every ring.
			// Made again only as `t` changes, so a chunk keeps its material, and its GPU binding, from frame to frame.
			if (c.made == null || c.made.base != t) {
				var wide = ring.chunk / RINGS[0].chunk, ux = c.cx * wide, uz = c.cz * wide;
				var offset = new ashui.draw3d.TextureTransform(t.scaleX * wide, t.scaleY * wide, t.rotation, t.offsetX + m.a * ux + m.b * uz,
					t.offsetY + m.c * ux + m.d * uz);
				c.made = {base: t, material: c.mesh.material.with({textureTransform: offset})};
			}
			ctx.drawMesh(c.mesh, ashui.math.Mat4.translation(new Vec3((c.cx + 0.5) * ring.chunk, -ring.drop, (c.cz + 0.5) * ring.chunk)), c.made.material);
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
	The drone's flight. It takes off from where it stands, playing its clip
	from `LIFT` to `HOVER`. It then flies forever along a slowly winding
	course, looping the clip's hover section from `HOVER` to `HOVER_END`
	and keeping its height above the ground ahead. Its controller node is
	held at its `HOVER` pose, so the clip's own turns do not fight the
	direction of flight.
**/
private class Flight {
	public static inline var LIFT = 5.0;
	public static inline var HOVER = 19.2;
	public static inline var HOVER_END = 24.4;
	public static inline var SPEED = 14.0;

	/** How high over the ground it cruises, climbing to it as the hover starts. **/
	public static inline var CRUISE = 16.0;

	public var x = 0.0;
	public var z = 0.0;
	public var heading = 0.0;
	public var ground:Float;
	public var elapsed = 0.0;
	public var travelled = 0.0;

	/** How far over the ground it has climbed. **/
	public var climb = 0.0;

	public function new()
		ground = EndlessTerrain.height(0, 0);

	/** Moves it on `dt` seconds. **/
	public function advance(dt:Float):Void {
		elapsed += dt;
		var flying = elapsed - (HOVER - LIFT - 4);
		// Up to speed over four seconds as the take-off ends.
		var speed = flying <= 0 ? 0 : SPEED * Math.min(1, flying / 4);
		travelled += speed * dt;
		// Round in a wide curve, weaving as it goes: in a couple of minutes it has faced every way, the whole sky passing over.
		heading = travelled / 160 + 0.5 * Math.sin(travelled / 70);
		x += Math.sin(heading) * speed * dt;
		z += Math.cos(heading) * speed * dt;
		// The highest ground a good way ahead, followed smoothly, so it rises before a hill; and its climb to cruising height.
		var ahead = -1e9;
		for (k in 0...6) {
			var d = k * 8;
			ahead = Math.max(ahead, EndlessTerrain.height(x + Math.sin(heading) * d, z + Math.cos(heading) * d));
		}
		if (speed > 0)
			ground += (ahead - ground) * Math.min(1, dt * 1.2);
		var t = Math.max(0, Math.min(1, flying / 6));
		climb = CRUISE * t * t * (3 - 2 * t);
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
	(CC-BY-NC-SA-4.0), with a faint haze, `HAZE`, around the horizon. The
	scene's fog uses the same colour, so the ground's far edge blends into
	the sky.
**/
private class AlienSky {
	public static inline var PANORAMA = "../../snapshot/assets/3d/sky_pano_-_milkyway/textures/lambert1_emissive.jpeg";

	/**
		Where the moonlight comes from: over the camera's shoulder, as a film
		lights a night shot, so what the camera sees of the drone is lit.
	**/
	public static final LIGHT = new Vec3(0.8, 0.55, -0.25).normalize();

	/** The moonlit rock's light, linear: its brown as the ground shows it. **/
	static final ROCK = new Vec3(0.11, 0.058, 0.032);

	/** The panorama's own colour round its horizon, averaged, `0xRRGGBB`: the fog's, so the ground's far edge fades into the sky behind it. **/
	public static inline var HAZE = 0x1f1917;

	/** How far the sky sphere turns its picture round: 0.27 of the way, in radians. **/
	public static inline var TURN = 1.696;

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
		var u = 0.5 + Math.atan2(d.x, -d.z) / (2 * Math.PI) + TURN / (2 * Math.PI);
		u -= Math.floor(u);
		// Upside down, as the sky sphere lays it.
		var v = 1 - Math.acos(Math.max(-1, Math.min(1, d.y))) / Math.PI;
		var x = Std.int(u * WIDTH) % WIDTH, y = Std.int(Math.min(HEIGHT - 1, v * HEIGHT));
		var o = (y * WIDTH + x) * 4;
		var c = new Vec3(linear[px.get(o)], linear[px.get(o + 1)], linear[px.get(o + 2)]).scale(1.6);
		// Haze thickening toward the horizon; below it, the ground's darkness.
		var haze = new Vec3(linear[HAZE >> 16 & 0xff], linear[HAZE >> 8 & 0xff], linear[HAZE & 0xff]);
		var low = 1 - Math.min(1, Math.abs(d.y) * 5);
		c = c.lerp(haze, low * 0.5);
		// Below the level, the moonlit rock the drone flies over, warm brown, fading into the haze toward the horizon:
		// what its metal reflects underneath, and what lights it from below.
		if (d.y < 0)
			c = haze.lerp(ROCK, Math.min(1, -d.y * 3));
		return c;
	}
}

/**
	The shader for the endless ground. It curves the ground away like a
	planet's surface: each vertex is lowered by the square of its distance
	from the camera divided by twice `RADIUS`, so the ground falls away to
	a curved horizon instead of ending at an edge. It also samples the rock
	so that its repeats do not form a visible grid.
**/
class CurvedGround implements hlwgpu.hxsl.Shader {
	public static inline var RADIUS = 4000.0;

	static var SRC = {
		@:extends ashui.core.render.MeshShader;

		function bend(world : Vec3) : Vec3 {
			var away = world.xz - cameraEye().xz;
			return world - vec3(0., dot(away, away) / (2. * 4000.), 0.);
		}

		/** Smooth noise 0 to 1 over the ground: a random value at each whole point, eased between. **/
		function groundNoise(p : Vec2) : Float {
			var i = floor(p);
			var f = p - i;
			var u = f * f * (vec2(3., 3.) - f * 2.);
			var a = fract(sin(dot(i, vec2(127.1, 311.7))) * 43758.5453);
			var b = fract(sin(dot(i + vec2(1., 0.), vec2(127.1, 311.7))) * 43758.5453);
			var c = fract(sin(dot(i + vec2(0., 1.), vec2(127.1, 311.7))) * 43758.5453);
			var d = fract(sin(dot(i + vec2(1., 1.), vec2(127.1, 311.7))) * 43758.5453);
			return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
		}

		/** A random value 0 to 1 for each corner of the hex grid, two of them. **/
		function cornerHash(v : Vec2) : Vec2 {
			return fract(sin(vec2(dot(v, vec2(127.1, 311.7)), dot(v, vec2(269.5, 183.3)))) * 43758.5453);
		}

		/** `uv` turned by the angle `h.x` names and moved by `h.y`: where a hex corner reads the rock. **/
		function cornerUv(uv : Vec2, h : Vec2) : Vec2 {
			var a = h.x * 6.2831853;
			var c = cos(a);
			var s = sin(a);
			return vec2(c * uv.x - s * uv.y, s * uv.x + c * uv.y) + vec2(h.y, fract(h.y * 7.31));
		}

		/** A normal map's slope read at a corner turned by `h.x`'s angle, turned back to the ground's way. **/
		function cornerSlope(n : Vec2, h : Vec2) : Vec2 {
			var a = h.x * 6.2831853;
			var c = cos(a);
			var s = sin(a);
			return vec2(c * n.x + s * n.y, -s * n.x + c * n.y);
		}

		/**
			The rock without a repeat, by hex tiling (Mikkelsen, "Practical
			Real-Time Hex-Tiling", 2022): the ground's texture coordinates are
			cut into a grid of triangles, and each corner reads the rock turned
			and moved its own random way; every point blends the three corners
			round it, by how near it is to each, sharpened, so no seam shows and
			no copy lines up with, or points the same way as, its neighbour.
			Steeper ground is darker and greyer, as weathered slopes are. Mip
			levels come from the coordinates before turning, as turning keeps
			their scale. The rock is 2048 texels square.
		**/
		function surface() {
			var settings = drawSurface(drawIndex);
			// Two hexes a repeat of the rock.
			var g = texcoord * 3.4641016;
			var sk = vec2(g.x - 0.57735027 * g.y, 1.15470054 * g.y);
			var base = floor(sk);
			var fr = sk - base;
			var tz = 1. - fr.x - fr.y;
			var s = tz < 0. ? 1. : 0.;
			var s2 = 2. * s - 1.;
			var w1 = -tz * s2;
			var w2 = s - fr.y * s2;
			var w3 = s - fr.x * s2;
			var h1 = cornerHash(base + vec2(s, s));
			var h2 = cornerHash(base + vec2(s, 1. - s));
			var h3 = cornerHash(base + vec2(1. - s, s));
			var u1 = cornerUv(texcoord, h1);
			var u2 = cornerUv(texcoord, h2);
			var u3 = cornerUv(texcoord, h3);
			// Sharpened toward the nearest corner, so blends are narrow and the rock keeps its contrast.
			w1 = w1 * w1 * w1 * w1;
			w2 = w2 * w2 * w2 * w2;
			w3 = w3 * w3 * w3 * w3;
			var total = max(w1 + w2 + w3, 0.0001);
			w1 /= total;
			w2 /= total;
			w3 /= total;
			var lod = max(0., log2(max(fwidth(texcoord.x), fwidth(texcoord.y)) * 2048.));
			var c = textureLod(baseColorMap, u1, lod).rgb * w1 + textureLod(baseColorMap, u2, lod).rgb * w2 + textureLod(baseColorMap, u3, lod).rgb * w3;
			var flat = normalize(worldNormal);
			var steep = smoothstep(0.92, 0.6, flat.y);
			var tint = 0.8 + 0.4 * groundNoise(worldPos.xz * 0.006 + vec2(7., 3.));
			var grey = vec3(1., 1., 1.) * dot(c, vec3(0.2126, 0.7152, 0.0722));
			c = mix(c, grey, steep * 0.35) * tint * (1. - 0.3 * steep);
			surfaceColor = vec4(c, 1.) * drawBaseColor(drawIndex);
			var mr = textureLod(metalRoughMap, u1, lod) * w1 + textureLod(metalRoughMap, u2, lod) * w2 + textureLod(metalRoughMap, u3, lod) * w3;
			surfaceMetallic = clamp(settings.x * mr.b, 0., 1.);
			surfaceRoughness = clamp(settings.y * mr.g, 0.04, 1.);
			var n = flat;
			if (drawFlags(drawIndex).x > 0.5) {
				var n1 = cornerSlope(textureLod(normalMap, u1, lod).xy * 2. - vec2(1., 1.), h1);
				var n2 = cornerSlope(textureLod(normalMap, u2, lod).xy * 2. - vec2(1., 1.), h2);
				var n3 = cornerSlope(textureLod(normalMap, u3, lod).xy * 2. - vec2(1., 1.), h3);
				var nxy = n1 * w1 + n2 * w2 + n3 * w3;
				var tn = vec3(nxy * settings.z, sqrt(max(1. - dot(nxy, nxy), 0.)));
				var t = worldTangent.xyz - n * dot(n, worldTangent.xyz);
				if (dot(t, t) > 0.00000001) {
					t = normalize(t);
					var bt = cross(n, t) * worldTangent.w;
					n = normalize(t * tn.x + bt * tn.y + n * tn.z);
				}
			}
			surfaceNormal = n;
			surfaceEmission = vec3(0., 0., 0.);
			var occ = textureLod(occlusionMap, u1, lod).r * w1 + textureLod(occlusionMap, u2, lod).r * w2 + textureLod(occlusionMap, u3, lod).r * w3;
			surfaceOcclusion = mix(1., occ, settings.w);
			toEye = normalize(cameraEye() - worldPos);
		}
	};
}
