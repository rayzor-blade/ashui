import ashui.canvaskit.SceneKit;
import ashui.canvaskit.CanvasKit;
import ashui.components.Accordion;
import ashui.components.Slider;
import ashui.components.Alert;
import ashui.components.Badge;
import ashui.components.Button;
import ashui.components.Card;
import ashui.components.Dialog;
import ashui.components.DropdownMenu;
import ashui.components.Popover;
import ashui.components.Toast;
import ashui.components.Checkbox;
import ashui.components.RadioGroup;
import ashui.components.Select;
import ashui.components.NumberInput;
import ashui.components.Toggle;
import ashui.components.Sheet;
import ashui.components.HoverCard;
import ashui.components.ContextMenu;
import ashui.components.Breadcrumb;
import ashui.components.Pagination;
import ashui.components.Table;
import ashui.components.Kbd;
import ashui.components.Menubar;
import ashui.components.NavigationMenu;
import ashui.components.ScrollArea;
import ashui.components.Command;
import ashui.components.Combobox;
import ashui.components.Calendar;
import ashui.components.Chart;
import ashui.components.Sidebar;
import ashui.components.AspectRatio;
import ashui.components.Avatar;
import ashui.components.AvatarGroup;
import ashui.components.InputOtp;
import ashui.components.Resizable;
import ashui.components.Drawer;
import ashui.components.TreeView;
import ashui.components.Typography;
import ashui.components.Separator;
import ashui.components.ToggleSwitch;
import ashui.components.Tabs;
import ashui.components.Tooltip;
import ashui.layout.LayoutTree;
import ashui.reactive.Owner;
import ashui.reactive.Signal;
import ashui.types.Style;
import ashui.ui.Div;
import ashui.ui.Hxx.hxx;

/** The ashui.components library: its sheet's place, its components' parts, states and behaviour. **/
class Components {
	static var failures = 0;

	static function check(what:String, ok:Bool, ?detail:Dynamic) {
		if (!ok) {
			failures++;
			Sys.println('FAIL $what' + (detail != null ? ': $detail' : ''));
		} else
			Sys.println('ok   $what');
	}

	static function identity2(tree:LayoutTree, id:haxe.Int64)
		return ashui.css.Identity.of(tree, id);

	static function key(k:window.Key, code:window.KeyCode, pressed = true):window.KeyEvent
		return Input(Code(code), k, None, Standard, pressed ? Pressed : Released, false, Unavailable);

	/** ashui-canvaskit: the orbit camera's moves, and that each shape's triangles face out. **/
	static function canvasKit() {
		var cam = new ashui.canvaskit.OrbitCamera(0, 0, 5, ashui.math.Vec3.ZERO);
		check("an orbit camera at azimuth and elevation 0 sits on +Z", cam.eye().distance(new ashui.math.Vec3(0, 0, 5)) < 1e-9, cam.eye());
		cam.orbit(Math.PI / 2, 0);
		check("a quarter turn round takes it to +X", cam.eye().distance(new ashui.math.Vec3(5, 0, 0)) < 1e-9, cam.eye());
		cam.orbit(0, 10);
		check("it rises no further than its limit, short of straight up", cam.elevation.get() == cam.maxElevation);
		cam.zoom(1e-6);
		check("and comes no nearer than its least distance", cam.distance.get() == cam.minDistance);
		cam.reset();
		cam.pan(0.5, 0);
		var t = cam.target.get();
		check("a pan moves the target across the view, not toward it", Math.abs(t.z) < 1e-9 && t.x > 0, t);
		cam.reset();
		cam.frame(new ashui.math.Vec3(-1, -1, -1), new ashui.math.Vec3(3, 1, 1));
		check("framing a box aims at its middle", cam.target.get().distance(new ashui.math.Vec3(1, 0, 0)) < 1e-9);
		function outward(name:String, mesh:ashui.draw3d.MeshData, ?centre:ashui.math.Vec3->ashui.math.Vec3) {
			var v = mesh.vertices, ix = mesh.indices, bad = 0;
			inline function at(i:Int)
				return new ashui.math.Vec3(v.getFloat(i * 48), v.getFloat(i * 48 + 4), v.getFloat(i * 48 + 8));
			var k = 0;
			while (k < mesh.indexCount) {
				var a = at(ix.getInt32(k * 4)), b = at(ix.getInt32(k * 4 + 4)), c = at(ix.getInt32(k * 4 + 8));
				var face = b.sub(a).cross(c.sub(a));
				var mid = a.add(b).add(c).scale(1 / 3);
				var from = centre != null ? centre(mid) : ashui.math.Vec3.ZERO;
				if (face.length() > 1e-12 && face.dot(mid.sub(from)) <= 0)
					bad++;
				k += 3;
			}
			check('$name: every triangle faces out, counter-clockwise seen from outside', bad == 0 && mesh.indexCount > 0, '$bad of ${Std.int(mesh.indexCount / 3)}');
		}
		outward("box", ashui.canvaskit.Geometry.box(1, 2, 3));
		outward("sphere", ashui.canvaskit.Geometry.sphere());
		outward("cylinder", ashui.canvaskit.Geometry.cylinder());
		// A torus's triangles face away from the middle of its tube, on the ring round its centre.
		outward("torus", ashui.canvaskit.Geometry.torus(1, 0.25), p -> new ashui.math.Vec3(p.x, 0, p.z).normalize());
		outward("plane", ashui.canvaskit.Geometry.plane(2, 2, 4), p -> p.sub(new ashui.math.Vec3(0, 1, 0)));

		// Environments: HDR decoding, cube directions, mip levels.
		var Env = ashui.canvaskit.Environment;
		inline function envNear(a:ashui.math.Vec3, b:ashui.math.Vec3)
			return a.distance(b) < 1e-9;
		check("16-bit floats: one, a half, zero, and the largest finite one for what is past it",
			Env.half(1) == 0x3C00 && Env.half(0.5) == 0x3800 && Env.half(0) == 0 && Env.half(1e9) == 0x7BFF, [Env.half(1), Env.half(0.5)]);
		check("a cube's +Z face looks along +Z through its middle, +Y up through its top edge",
			envNear(Env.direction(4, 0, 0), new ashui.math.Vec3(0, 0, 1)) && Env.direction(4, 0, -1).y > 0.7, Env.direction(4, 0, -1));
		check("its +Y face looks up", envNear(Env.direction(2, 0, 0), ashui.math.Vec3.UP));
		// A Radiance file of two rows of four flat pixels, then one of rows eight wide, run-length encoded.
		function hdr(width:Int, height:Int, body:Array<Int>):haxe.io.Bytes {
			var head = haxe.io.Bytes.ofString('#?RADIANCE\nFORMAT=32-bit_rle_rgbe\n\n-Y $height +X $width\n');
			var b = haxe.io.Bytes.alloc(head.length + body.length);
			b.blit(0, head, 0, head.length);
			for (i in 0...body.length)
				b.set(head.length + i, body[i]);
			return b;
		}
		var flat = ashui.canvaskit.Environment.Rgbe.decode(hdr(4, 2, [for (_ in 0...8) for (v in [128, 64, 32, 129]) v]));
		var c = flat.sample(new ashui.math.Vec3(0, 0, -1));
		check("an .hdr's pixels decode to their colour times two to their exponent", Math.abs(c.x - 128.5 / 128) < 1e-6 && Math.abs(c.z - 32.5 / 128) < 1e-6, c);
		var rle = ashui.canvaskit.Environment.Rgbe.decode(hdr(8, 1, [2, 2, 0, 8, 136, 200, 136, 100, 136, 50, 136, 136]));
		var d = rle.sample(new ashui.math.Vec3(0, 1, 0));
		check("and run-length encoded rows decode too", Math.abs(d.x - 200.5) < 1e-6 && Math.abs(d.y - 100.5) < 1e-6, d);
		var sky = ashui.canvaskit.Environment.gradient(0x3366ff, 0xffffff, 0x222222, 1, 8);
		check("an environment has every mip level down to a texel a face", sky.levels == 4 && sky.faces[3].length == 6 * 8 && sky.faces[0].length == 6 * 64 * 8);


		// <scene-kit>: a drag turns its camera, a shift-drag pans it, the wheel zooms it.
		var orbit = new ashui.canvaskit.OrbitCamera(0, 0.2, 5);
		var kitTree = new LayoutTree();
		var kitRoot:Div = Owner.root(kitTree, _ -> <div width={400} height={300}><scene-kit camera={orbit} width={400} height={300} /></div>);
		kitTree.flush();
		kitTree.computeLayout(kitRoot.node, 400, 300);
		ashui.input.Pointer.move(kitTree, 200, 150);
		ashui.input.Pointer.press(kitTree);
		ashui.input.Pointer.move(kitTree, 260, 120);
		ashui.input.Pointer.release(kitTree);
		check("<scene-kit>: dragging right turns the camera the other way round, so the scene turns with the drag", orbit.azimuth.get() < 0, orbit.azimuth.get());
		check("and dragging up lowers it", orbit.elevation.get() < 0.2, orbit.elevation.get());
		ashui.input.Pointer.move(kitTree, 200, 150);
		ashui.input.Pointer.wheel(kitTree, 0, 200);
		check("scrolling down moves it further away", orbit.distance.get() > 5, orbit.distance.get());
		var before = orbit.target.get();
		ashui.input.Pointer.modifiers(kitTree, State(true, false, false, false, Unknown, Unknown, Unknown, Unknown, Unknown, Unknown, Unknown, Unknown));
		ashui.input.Pointer.press(kitTree);
		ashui.input.Pointer.move(kitTree, 240, 150);
		ashui.input.Pointer.release(kitTree);
		check("a shift-drag moves the target, not the turn", orbit.target.get().distance(before) > 0, orbit.target.get());
	}

	/** ashui-canvaskit's 2D kit: the viewport's maths, the spatial index, and <canvas-kit>'s selection, dragging, panning and zoom. **/
	static function canvasKit2D() {
		var view = new ashui.canvaskit.Viewport2D();
		view.panBy(40, 20);
		var p = view.contentToScreen(0, 0);
		check("Viewport2D: a pan moves the content by as many screen pixels", p.x == 40 && p.y == 20, p);
		var under = view.screenToContent(100, 80);
		view.zoomAt(100, 80, 2);
		var still = view.screenToContent(100, 80);
		check("Viewport2D: zooming about a point keeps the content under it", Math.abs(still.x - under.x) < 1e-9 && Math.abs(still.y - under.y) < 1e-9, [under, still]);
		view.zoomAt(0, 0, 1000);
		check("and the zoom stays within its limit", view.zoom.get() == view.maxZoom, view.zoom.get());
		var fit = view.fitting(100, 100, 200, 100, 400, 300, 0);
		check("Viewport2D: fitting a 200x100 rect into 400x300 zooms 2 and centres it",
			fit.zoom == 2 && Math.abs(2 * (200 + fit.panX) - 200) < 1e-9 && Math.abs(2 * (150 + fit.panY) - 150) < 1e-9, fit);

		var index = new ashui.canvaskit.SpatialIndex(50);
		index.set("a", 0, 0, 100, 100);
		index.set("b", 50, 50, 100, 100);
		check("SpatialIndex: a point where two overlap hits the later", index.hitTest(75, 75).id == "b");
		check("and one only the first covers hits it", index.hitTest(10, 10).id == "a");
		check("an area finds every rectangle it touches, bottom first", index.query(90, 90, 20, 20).join(",") == "a,b", index.query(90, 90, 20, 20));
		index.remove("b");
		check("a removed rectangle is gone from every cell", index.hitTest(75, 75).id == "a" && index.hitTest(140, 140) == null && index.length == 1);
		index.set("a", 500, 500, 10, 10);
		check("set again, it moves", index.hitTest(10, 10) == null && index.hitTest(505, 505).id == "a");

		// <canvas-kit> with two boxes the app moves as they are dragged.
		var items = [{id: "a", x: 0.0, y: 0.0}, {id: "b", x: 200.0, y: 100.0}];
		var viewport = new ashui.canvaskit.Viewport2D();
		var selection = new ashui.canvaskit.Selection2D();
		var clicked = [];
		var tree = new LayoutTree();
		var root:Div = Owner.root(tree, _ -> <div width={400} height={300}><canvas-kit viewport={viewport} selection={selection} snap={10.0} width={400} height={300}
			draw={(ctx, kit) -> for (it in items) kit.region(it.id, it.x, it.y, 80, 50)}
			onDrag={(ids, dx, dy) -> for (it in items) if (ids.indexOf(it.id) >= 0) { it.x += dx; it.y += dy; }}
			onClick={(id, _) -> clicked.push(id)} /></div>);
		tree.flush();
		tree.computeLayout(root.node, 400, 300);
		tree.flush();
		function drag(x0:Float, y0:Float, x1:Float, y1:Float, ?shift:Bool) {
			ashui.input.Pointer.modifiers(tree, State(shift == true, false, false, false, Unknown, Unknown, Unknown, Unknown, Unknown, Unknown, Unknown, Unknown));
			ashui.input.Pointer.move(tree, x0, y0);
			ashui.input.Pointer.press(tree);
			ashui.input.Pointer.move(tree, (x0 + x1) / 2, (y0 + y1) / 2);
			ashui.input.Pointer.move(tree, x1, y1);
			ashui.input.Pointer.release(tree);
			tree.flush();
		}
		drag(20, 20, 20, 20);
		check("<canvas-kit>: a click on a box selects it and is reported", selection.ids.get().join(",") == "a" && clicked.join(",") == "a", [selection.ids.get(), clicked]);
		drag(20, 20, 53, 41);
		check("dragging it moves it by the drag, snapped to the grid", items[0].x == 30 && items[0].y == 20, items[0]);
		drag(220, 120, 220, 120, true);
		check("a shift-click adds the other to the selection", selection.ids.get().join(",") == "a,b", selection.ids.get());
		drag(380, 280, 380, 280);
		check("a click on the empty canvas clears it", selection.ids.get().length == 0, selection.ids.get());
		drag(5, 5, 390, 290, true);
		check("a shift-drag over the empty canvas selects every box the selection box touches", selection.ids.get().join(",") == "a,b", selection.ids.get());
		var panBefore = viewport.panX.get();
		drag(380, 20, 340, 20);
		check("a drag of the empty canvas pans the view", viewport.panX.get() == panBefore - 40, viewport.panX.get());
		ashui.input.Pointer.modifiers(tree, State(false, false, false, false, Unknown, Unknown, Unknown, Unknown, Unknown, Unknown, Unknown, Unknown));
		ashui.input.Pointer.move(tree, 100, 100);
		ashui.input.Pointer.wheel(tree, 0, -200);
		check("scrolling up zooms in", viewport.zoom.get() > 1, viewport.zoom.get());
	}

	/** ashui-canvaskit's glTF texture cap: the helmet's 2048-pixel textures read at 512 or under, the same shape. **/
	static function gltfTextureCap() {
		var path = "../../tools/snapshot/assets/3d/DamagedHelmet/DamagedHelmet.gltf";
		function sizes(scene:ashui.canvaskit.Gltf):Array<String> {
			var out = [];
			for (d in scene.draws) {
				var m = d.mesh.material;
				for (b in [m.baseColorTexture, m.normalTexture, m.metallicRoughnessTexture, m.emissiveTexture, m.occlusionTexture])
					if (b != null)
						out.push('${b.width}x${b.height}');
			}
			return out;
		}
		var full = sizes(ashui.canvaskit.Gltf.load(path));
		var capped = sizes(ashui.canvaskit.Gltf.load(path, {maxTextureSize: 512}));
		check("glTF texture cap: the helmet's textures are 2048 pixels uncapped", full.length > 0 && full.filter(s -> s == "2048x2048").length == full.length, full);
		check("glTF texture cap: read at 512 with the cap, as many of them", capped.length == full.length && capped.filter(s -> s == "512x512").length == capped.length, capped);
		var wide = ashui.types.Bitmap.fromBytes(ashui.core.render.Png.encode(1000, 300, haxe.io.Bytes.alloc(1000 * 300 * 4)));
		wide.shrink(512);
		check("glTF texture cap: a wide image keeps its shape, each side a multiple of 4", wide.width == 512 && wide.height == 152, [wide.width, wide.height]);
	}

	/** ashui-canvaskit's glTF: a skinned, morphed, animated file read whole, and a pose played from it. **/
	static function gltf() {
		var b = haxe.io.Bytes.alloc(420);
		var o = 0;
		function f(v:Float) {
			b.setFloat(o, v);
			o += 4;
		}
		function u(v:Int) {
			b.setUInt16(o, v);
			o += 2;
		}
		for (v in [0.0, 0, 0, 1, 0, 0, 0, 1, 0]) f(v); // positions, at 0
		for (_ in 0...3) for (j in [0, 1, 0, 0]) u(j); // joints, at 36
		for (_ in 0...3) for (w in [0.5, 0.5, 0, 0]) f(w); // weights, at 60
		for (m in [ashui.math.Mat4.IDENTITY, ashui.math.Mat4.translation(new ashui.math.Vec3(0, -1, 0))]) for (c in 0...4) for (r in 0...4) f(m.get(c, r)); // inverse binds, at 108
		for (t in [0.0, 1]) f(t); // times, at 236
		for (v in [0.0, 1, 0, 2, 1, 0]) f(v); // the tip's translation, at 244
		var s = Math.sin(Math.PI / 4), c = Math.cos(Math.PI / 4);
		for (v in [0.0, 0, 0, 1, 0, s, 0, c]) f(v); // the root's turn to a quarter about y, at 268
		for (v in [0.0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 4, 0, 0, 0, 0, 0]) f(v); // a cubic spline from 0 to 4 in x, flat tangents, at 300
		for (v in [1.0, 1, 1, 3, 3, 3]) f(v); // stepped scale, at 372
		u(2); u(0); // the sparse target's index, at 396
		for (v in [0.0, 0, 5]) f(v); // and its value, at 400
		for (v in [0.0, 1]) f(v); // the morph weight, at 412
		var json = {
			asset: {version: "2.0"},
			scene: 0,
			scenes: [{nodes: [0, 1, 3]}],
			nodes: ([
				{name: "body", mesh: 0, skin: 0},
				{name: "root", children: [2]},
				{name: "tip", translation: [0, 1, 0]},
				{name: "prop", mesh: 1}
			] : Array<Dynamic>),
			meshes: ([
				{primitives: [{attributes: {POSITION: 0, JOINTS_0: 1, WEIGHTS_0: 2}, targets: [{POSITION: 9}]}]},
				{primitives: [{attributes: {POSITION: 0}, material: 0}]}
			] : Array<Dynamic>),
			materials: [{
				pbrMetallicRoughness: {
					baseColorTexture: {index: 0, extensions: {KHR_texture_transform: {scale: [3, 2], rotation: 0.5, offset: [0.25, 0.75]}}}
				}
			}],
			textures: [{source: 0}],
			images: [{uri: "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGP4z/AfAAQAAf8iCjrwAAAAAElFTkSuQmCC"}],
			skins: [{joints: [1, 2], inverseBindMatrices: 3}],
			animations: [{
				name: "wave",
				samplers: ([
					{input: 4, output: 5},
					{input: 4, output: 6},
					{input: 4, output: 7, interpolation: "CUBICSPLINE"},
					{input: 4, output: 8, interpolation: "STEP"},
					{input: 4, output: 10}
				] : Array<Dynamic>),
				channels: ([
					{sampler: 0, target: {node: 2, path: "translation"}},
					{sampler: 1, target: {node: 1, path: "rotation"}},
					{sampler: 2, target: {node: 3, path: "translation"}},
					{sampler: 3, target: {node: 3, path: "scale"}},
					{sampler: 4, target: {node: 0, path: "weights"}}
				] : Array<Dynamic>)
			}],
			buffers: [{byteLength: 420, uri: "data:application/octet-stream;base64," + haxe.crypto.Base64.encode(b)}],
			bufferViews: [{buffer: 0, byteLength: 420}],
			accessors: ([
				{bufferView: 0, byteOffset: 0, componentType: 5126, count: 3, type: "VEC3"},
				{bufferView: 0, byteOffset: 36, componentType: 5123, count: 3, type: "VEC4"},
				{bufferView: 0, byteOffset: 60, componentType: 5126, count: 3, type: "VEC4"},
				{bufferView: 0, byteOffset: 108, componentType: 5126, count: 2, type: "MAT4"},
				{bufferView: 0, byteOffset: 236, componentType: 5126, count: 2, type: "SCALAR"},
				{bufferView: 0, byteOffset: 244, componentType: 5126, count: 2, type: "VEC3"},
				{bufferView: 0, byteOffset: 268, componentType: 5126, count: 2, type: "VEC4"},
				{bufferView: 0, byteOffset: 300, componentType: 5126, count: 6, type: "VEC3"},
				{bufferView: 0, byteOffset: 372, componentType: 5126, count: 2, type: "VEC3"},
				{componentType: 5126, count: 3, type: "VEC3", sparse: {count: 1, indices: {bufferView: 0, byteOffset: 396, componentType: 5123}, values: {bufferView: 0, byteOffset: 400}}},
				{bufferView: 0, byteOffset: 412, componentType: 5126, count: 2, type: "SCALAR"}
			] : Array<Dynamic>)
		};
		var scene = ashui.canvaskit.Gltf.parse(haxe.io.Bytes.ofString(haxe.Json.stringify(json)), _ -> null);
		inline function near(a:ashui.math.Vec3, x:Float, y:Float, z:Float)
			return a.distance(new ashui.math.Vec3(x, y, z)) < 1e-5;
		check("glTF: the node tree, a child knowing its parent", scene.nodes.length == 4 && scene.nodes[2].parent == 1 && scene.nodes[1].parent == -1
			&& scene.roots.join(",") == "0,1,3", [for (n in scene.nodes) n.parent]);
		var body = scene.meshes[0].primitives[0];
		check("glTF: each vertex's joints and weights", body.joints != null && body.joints[1] == 1 && body.weights[0] == 0.5,
			body.joints != null ? [body.joints[0], body.joints[1]] : null);
		check("glTF: a skin's joints and inverse bind matrices", scene.skins[0].joints.join(",") == "1,2"
			&& near(scene.skins[0].inverseBindMatrices[1].position(), 0, -1, 0), scene.skins[0].inverseBindMatrices[1].position());
		var target = body.targets[0].positions;
		check("glTF: a sparse morph target, zero but where it lists", target != null && target[5] == 0 && target[8] == 5 && scene.meshes[0].weights.length == 1,
			target != null ? [for (i in 0...9) target[i]] : null);
		var wave = scene.animation("wave");
		check("glTF: an animation's channels and its length", wave != null && wave.channels.length == 5 && wave.duration == 1, wave);
		check("glTF: drawn at rest, every mesh where its node is", scene.draws.length == 2, scene.draws.length);
		var placed = scene.meshes[1].primitives[0].mesh.material.textureTransform;
		check("glTF: KHR_texture_transform's scale, rotation and offset", placed != null && placed.scaleX == 3 && placed.scaleY == 2
			&& placed.rotation == 0.5 && placed.offsetX == 0.25 && placed.offsetY == 0.75, placed);

		var pose = new ashui.canvaskit.GltfPose(scene);
		pose.play(wave, 0.5);
		check("pose: linear translation halfway", near(pose.translations[2], 1, 1, 0), pose.translations[2]);
		var half = pose.rotations[1];
		check("pose: a rotation slerped halfway, an eighth of a turn",
			Math.abs(half.y - Math.sin(Math.PI / 8)) < 1e-5 && Math.abs(half.w - Math.cos(Math.PI / 8)) < 1e-5, half);
		check("pose: a step keeps the keyframe before", near(pose.scales[3], 1, 1, 1), pose.scales[3]);
		check("pose: the morph weight halfway", Math.abs(pose.weights[0][0] - 0.5) < 1e-6, pose.weights[0]);
		pose.play(wave, 0.25);
		check("pose: a cubic spline eases, flat tangents giving 0.625 of the way at a quarter", near(pose.translations[3], 0.625, 0, 0), pose.translations[3]);
		pose.play(wave, 1.5);
		check("pose: past the end, the last keyframe", near(pose.scales[3], 3, 3, 3) && near(pose.translations[3], 4, 0, 0), [pose.scales[3], pose.translations[3]]);
		var world = pose.world();
		check("pose: a child in the scene through its parent's turn", near(world[2].position(), 0, 1, -2), world[2].position());
		pose.reset();
		var joints = pose.joints(0);
		check("pose: at rest each joint matrix is the identity", near(joints[1].position(), 0, 0, 0) && near(joints[0].position(), 0, 0, 0),
			[joints[0].position(), joints[1].position()]);
		var buffer = haxe.io.Bytes.alloc(2 * ashui.canvaskit.GltfPose.MATRIX_BYTES);
		pose.play(wave, 1);
		pose.update();
		pose.palette(0, buffer);
		check("pose: a skin's palette, ready to upload, the tip's joint turned and moved", Math.abs(buffer.getFloat(64 + 48) - 0) < 1e-5
			&& Math.abs(buffer.getFloat(64 + 52) - 0) < 1e-5 && Math.abs(buffer.getFloat(64 + 56) + 2) < 1e-5,
			[for (k in 12...15) buffer.getFloat(64 + k * 4)]);
		#if (ash_simd && hl)
		// Through ash-simd and through plain Haxe, the same numbers.
		var same = true;
		for (ch in wave.channels)
			for (step in 0...11) {
				var a = [0.0, 0, 0, 0], b = [0.0, 0, 0, 0];
				@:privateAccess ch.sampler.blend(step / 10, a, ch.path == Rotation, true);
				@:privateAccess ch.sampler.blend(step / 10, b, ch.path == Rotation, false);
				for (k in 0...ch.sampler.width)
					if (Math.abs(a[k] - b[k]) > 1e-6)
						same = false;
			}
		var ma = haxe.io.Bytes.alloc(64), mb = haxe.io.Bytes.alloc(64), sa = haxe.io.Bytes.alloc(64), sb = haxe.io.Bytes.alloc(64);
		for (k in 0...16) {
			ma.setFloat(k * 4, Math.sin(k + 1));
			mb.setFloat(k * 4, Math.cos(k * 3));
		}
		@:privateAccess ashui.canvaskit.GltfPose.multiply(ma, 0, mb, 0, sa, 0, true);
		@:privateAccess ashui.canvaskit.GltfPose.multiply(ma, 0, mb, 0, sb, 0, false);
		for (k in 0...16)
			if (Math.abs(sa.getFloat(k * 4) - sb.getFloat(k * 4)) > 1e-5)
				same = false;
		check("glTF sampling and matrix products are the same through ash-simd as through plain Haxe", same);
		#end
	}

	static function main() {
		ashui.theme.ThemeState.init(ashui.theme.themes.DefaultTheme.bundle(), Light);
		var tree = new LayoutTree();
		var clicks = 0;
		var on = Signal.make(false);
		var tab = Signal.make("account");
		var page:Div = Owner.root(tree, _ -> hxx('
			<div width={600} height={600} flexDirection={Column} alignItems={Start} gap={8}>
				<button variant={Outline} size={Sm} onClick={_ -> clicks++}>Save</button>
				<badge variant={Success}>New</badge>
				<card><card-header><card-title>Title</card-title><card-description>Words</card-description></card-header></card>
				<alert variant={Destructive}><alert-title>Oops</alert-title></alert>
				<separator orientation="vertical" />
				<toggle-switch checked={on} />
				<tabs value={tab}>
					<tabs-list><tabs-trigger value="account">Account</tabs-trigger><tabs-trigger value="password">Password</tabs-trigger></tabs-list>
					<tabs-content value="account">A</tabs-content>
					<tabs-content value="password">P</tabs-content>
				</tabs>
				<tooltip label="Saves your work" delay={0.2}><div width={40} height={20} /></tooltip>
			</div>
		'));
		function settle() {
			tree.flush();
			tree.computeLayout(page.node, 600, 600);
			tree.flush();
		}
		settle();
		var kids = tree.children(page.node.id);
		function identity(id:haxe.Int64)
			return ashui.css.Identity.of(tree, id);
		function clickAt(id:haxe.Int64) {
			var b = tree.getBounds(new ashui.layout.Node(id));
			ashui.input.Pointer.move(tree, b.x + b.width / 2, b.y + b.height / 2);
			ashui.input.Pointer.press(tree);
			ashui.input.Pointer.release(tree);
			settle();
		}

		var sheets:Array<ashui.css.Stylesheet> = @:privateAccess ashui.css.Css.sheets;
		var library = @:privateAccess ashui.css.Css.libraries.get("ashui-components");
		var page2 = ashui.css.Css.load(".x { width: 1px }");
		check("the library's sheet is in force after the user-agent sheet, before the page's", library != null
			&& sheets.indexOf(library) == sheets.indexOf(ashui.css.Css.userAgent) + 1 && sheets.indexOf(page2) > sheets.indexOf(library),
			[for (s in sheets) s == library ? "library" : s == ashui.css.Css.userAgent ? "ua" : "page"]);
		check("its sheet reads with no problems", library.diagnostics.length == 0, library.report());

		var button = identity(kids[0]);
		check("an imported Button is <button>: the built-in element, its variant and size attributes", button.types.indexOf("button") >= 0
			&& button.hasClass("ui-button") && button.attribute("data-variant") == "outline" && button.attribute("data-size") == "sm",
			[button.types, button.classes()]);
		clickAt(kids[0]);
		check("a Button is clicked as a button is", clicks == 1, clicks);
		check("a Badge, a Card's parts and an Alert's carry their classes and variants", identity(kids[1]).attribute("data-variant") == "success"
			&& identity(kids[2]).hasClass("ui-card") && identity(tree.children(kids[2])[0]).hasClass("ui-card-header")
			&& identity(kids[3]).attribute("data-variant") == "destructive");
		check("a vertical Separator says so", identity(kids[4]).attribute("data-orientation") == "vertical");

		var switchId = kids[5];
		clickAt(switchId);
		check("a ToggleSwitch turns when clicked, its signal, data-state and :checked with it", on.get() && identity(switchId).attribute("data-state") == "on"
			&& ashui.input.Interaction.byId(tree, switchId).checked.get(), [on.get(), identity(switchId).attribute("data-state")]);
		on.set(false);
		settle();
		check("and follows its signal", identity(switchId).attribute("data-state") == "off");

		var tabsId = kids[6];
		var tabsKids = tree.children(tabsId);
		var triggers = tree.children(tabsKids[0]);
		var stateOf = (id:haxe.Int64) -> identity(id).attribute("data-state");
		var first = [stateOf(triggers[0]), stateOf(triggers[1]), stateOf(tabsKids[1]), stateOf(tabsKids[2])].join(",");
		clickAt(triggers[1]);
		var afterClick = [stateOf(triggers[0]), stateOf(triggers[1]), stateOf(tabsKids[1]), stateOf(tabsKids[2])].join(",");
		check("Tabs show the content of the trigger chosen, by data-state, and set their signal",
			first == "active,inactive,active,inactive" && afterClick == "inactive,active,inactive,active" && tab.get() == "password", [first, afterClick]);
		ashui.input.Keyboard.input(tree, key(Named(ArrowLeft), ArrowLeft));
		settle();
		check("the arrows move among the triggers, choosing as they go", tab.get() == "account", tab.get());

		var tipId = kids[7];
		var tipState = () -> identity(tipId).attribute("data-state");
		var tb = tree.getBounds(new ashui.layout.Node(tipId));
		ashui.input.Pointer.move(tree, tb.x + 5, tb.y + 5);
		settle();
		var waiting = tipState(), before = ashui.ui.TopLayer.openEntries().length;
		ashui.animation.AnimationScheduler.main.tick(0.3);
		settle();
		var open = tipState(), shown = ashui.ui.TopLayer.openEntries().length;
		var rootKids = tree.children(page.node.id).length;
		ashui.input.Pointer.move(tree, 590, 590);
		settle();
		var closing = tipState(), stillDrawn = tree.children(page.node.id).length == rootKids;
		ashui.animation.AnimationScheduler.main.tick(0.5);
		settle();
		check("a Tooltip waits, opens after its delay, fades as the pointer leaves, then closes, each its data-state",
			waiting == "waiting" && before == 0 && open == "open" && shown == 1 && closing == "closing" && stillDrawn && tipState() == "closed"
			&& tree.children(page.node.id).length == rootKids - 1, [waiting, open, closing, tipState(), stillDrawn]);

		// --- Accordion: one item open at a time, opening by layout animation ---
		var accTree = new LayoutTree();
		var openItems = Signal.make(([] : Array<String>));
		var accRoot:Div = Owner.root(accTree, _ -> hxx('
			<div width={400} height={400} flexDirection={Column}>
				<accordion value={openItems}>
					<accordion-item value="a"><accordion-trigger>First</accordion-trigger><accordion-content><div height={60} /></accordion-content></accordion-item>
					<accordion-item value="b"><accordion-trigger>Second</accordion-trigger><accordion-content><div height={60} /></accordion-content></accordion-item>
				</accordion>
			</div>
		'));
		function accSettle() {
			accTree.flush();
			accTree.computeLayout(accRoot.node, 400, 400);
			accTree.flush();
		}
		accSettle();
		var accordion = accTree.children(accRoot.node.id)[0];
		var accItems = accTree.children(accordion);
		var firstTrigger = accTree.children(accItems[0])[0], firstContent = accTree.children(accItems[0])[1];
		var closedHeight = accTree.getBounds(new ashui.layout.Node(firstContent)).height;
		var tb2 = accTree.getBounds(new ashui.layout.Node(firstTrigger));
		ashui.input.Pointer.move(accTree, tb2.x + 10, tb2.y + 5);
		ashui.input.Pointer.press(accTree);
		ashui.input.Pointer.release(accTree);
		accSettle();
		var openHeight = accTree.getBounds(new ashui.layout.Node(firstContent)).height;
		var anims:Map<String, ashui.animation.LayoutAnimation> = @:privateAccess ashui.animation.LayoutAnimation.animated.get(accTree);
		var growing = @:privateAccess anims.get(haxe.Int64.toStr(firstContent)).running;
		var secondSliding = @:privateAccess anims.get(haxe.Int64.toStr(accItems[1])).shown.dy < 0;
		ashui.animation.AnimationScheduler.main.tick(1);
		check("an accordion item opens on its trigger, growing by layout animation as the next makes room", closedHeight == 0 && openHeight >= 60
			&& openItems.get().join(",") == "a" && growing && secondSliding && identity2(accTree, firstContent).attribute("data-state") == "open",
			[closedHeight, openHeight, growing, secondSliding]);
		var secondTrigger = accTree.children(accItems[1])[0];
		var sb = accTree.getBounds(new ashui.layout.Node(secondTrigger));
		ashui.input.Pointer.move(accTree, sb.x + 10, sb.y + 5);
		ashui.input.Pointer.press(accTree);
		ashui.input.Pointer.release(accTree);
		accSettle();
		check("one open at a time: opening the second closes the first", openItems.get().join(",") == "b", openItems.get());

		// --- Dialog and AlertDialog: open from a trigger, close from a close button, Escape only for a dialog ---
		var dlgTree = new LayoutTree();
		var dlgOpen = Signal.make(false), alertOpen = Signal.make(false);
		var dlgRoot:Div = Owner.root(dlgTree, _ -> hxx('
			<div width={600} height={400} flexDirection={Column} gap={8}>
				<dialog open={dlgOpen}>
					<dialog-trigger id="open">Open</dialog-trigger>
					<dialog-content><dialog-header><dialog-title>Title</dialog-title></dialog-header>
						<dialog-footer><dialog-close id="close">Cancel</dialog-close></dialog-footer></dialog-content>
				</dialog>
				<alert-dialog open={alertOpen}>
					<dialog-trigger id="ask">Delete</dialog-trigger>
					<alert-dialog-content><dialog-footer><dialog-close id="no">Cancel</dialog-close></dialog-footer></alert-dialog-content>
				</alert-dialog>
			</div>
		'));
		function dlgSettle() {
			dlgTree.flush();
			dlgTree.computeLayout(dlgRoot.node, 600, 400);
			dlgTree.flush();
			dlgTree.computeLayout(dlgRoot.node, 600, 400);
		}
		function find(at:haxe.Int64, id:String):Null<haxe.Int64> {
			var identity = identity2(dlgTree, at);
			if (identity != null && identity.id == id)
				return at;
			for (c in dlgTree.children(at)) {
				var f = find(c, id);
				if (f != null)
					return f;
			}
			return null;
		}
		function press(id:String) {
			// Past any opening animation: a panel growing from nothing is not yet where a press lands.
			ashui.animation.AnimationScheduler.main.tick(0.5);
			dlgSettle();
			var b = dlgTree.getBounds(new ashui.layout.Node(find(dlgRoot.node.id, id)));
			ashui.input.Pointer.move(dlgTree, b.x + b.width / 2, b.y + b.height / 2);
			ashui.input.Pointer.press(dlgTree);
			ashui.input.Pointer.release(dlgTree);
			dlgSettle();
		}
		dlgSettle();
		var rootShown = dlgTree.getBounds(new ashui.layout.Node(dlgTree.children(dlgRoot.node.id)[0])).height > 0;
		check("a Dialog's root is not HTML's closed dialog: its trigger shows", rootShown);
		press("open");
		var opened = dlgOpen.get() && ashui.ui.TopLayer.openEntries().length == 1;
		var focusRing = ashui.input.Focus.of(dlgTree) != null && ashui.input.Focus.of(dlgTree).focusVisible.get();
		press("close");
		check("a DialogTrigger opens it, a DialogClose closes it; opened by a press, its first control takes focus without a ring",
			opened && !focusRing && !dlgOpen.get(), [opened, focusRing, dlgOpen.get()]);
		press("open");
		ashui.input.Keyboard.input(dlgTree, key(Named(Escape), Escape));
		dlgSettle();
		check("Escape closes a dialog", !dlgOpen.get());
		press("ask");
		ashui.input.Keyboard.input(dlgTree, key(Named(Escape), Escape));
		dlgSettle();
		var stayed = alertOpen.get();
		press("no");
		check("an AlertDialog stays open on Escape; its own action closes it", stayed && !alertOpen.get(), [stayed, alertOpen.get()]);

		// --- Popover and DropdownMenu: anchored panels; a menu's keys ---
		var flTree = new LayoutTree();
		var popOpen = Signal.make(false), menuOpen = Signal.make(false), picked = Signal.make("");
		var flRoot:Div = Owner.root(flTree, _ -> hxx('
			<div width={600} height={400} flexDirection={Row} gap={40} padding={20} alignItems={Start}>
				<popover open={popOpen}><popover-trigger id="p">Open</popover-trigger><popover-content><p>Hi</p></popover-content></popover>
				<dropdown-menu open={menuOpen}>
					<dropdown-menu-trigger id="m">Options</dropdown-menu-trigger>
					<dropdown-menu-content>
						<dropdown-menu-item onSelect={() -> picked.set("one")}>One</dropdown-menu-item>
						<dropdown-menu-item disabled={true}>Off</dropdown-menu-item>
						<dropdown-menu-item onSelect={() -> picked.set("two")}>Two</dropdown-menu-item>
					</dropdown-menu-content>
				</dropdown-menu>
			</div>
		'));
		function flSettle() {
			ashui.animation.AnimationScheduler.main.tick(0.5);
			flTree.flush();
			flTree.computeLayout(flRoot.node, 600, 400);
			flTree.flush();
			flTree.computeLayout(flRoot.node, 600, 400);
		}
		function flFind(at:haxe.Int64, id:String):Null<haxe.Int64> {
			var identity = identity2(flTree, at);
			if (identity != null && identity.id == id)
				return at;
			for (c in flTree.children(at)) {
				var f = flFind(c, id);
				if (f != null)
					return f;
			}
			return null;
		}
		function flPress(id:String) {
			flSettle();
			var b = flTree.getBounds(new ashui.layout.Node(flFind(flRoot.node.id, id)));
			ashui.input.Pointer.move(flTree, b.x + b.width / 2, b.y + b.height / 2);
			ashui.input.Pointer.press(flTree);
			ashui.input.Pointer.release(flTree);
			flSettle();
		}
		flSettle();
		flPress("p");
		var popShown = popOpen.get() && ashui.ui.TopLayer.openEntries().length == 1;
		var trigger = flTree.getBounds(new ashui.layout.Node(flFind(flRoot.node.id, "p")));
		var panel = ashui.ui.TopLayer.openEntries()[0].content;
		var pb = flTree.getBounds(panel.node);
		var below = pb != null && Math.abs(pb.y - (trigger.y + trigger.height + 4)) < 1.5;
		ashui.input.Keyboard.input(flTree, key(Named(Escape), Escape));
		flSettle();
		check("a Popover opens under its trigger, 4 from it, and Escape closes it", popShown && below && !popOpen.get(), [popShown, below, popOpen.get()]);

		ashui.input.Keyboard.input(flTree, key(Named(Tab), Tab));
		flSettle();
		var m = ashui.input.Interaction.byId(flTree, flFind(flRoot.node.id, "m"));
		ashui.input.Focus.set(m, true);
		ashui.input.Keyboard.input(flTree, key(Named(Enter), Enter));
		ashui.input.Keyboard.input(flTree, key(Named(Enter), Enter, false));
		flSettle();
		var firstFocused = ashui.input.Focus.of(flTree);
		var firstIsOne = firstFocused != null && identity2(flTree, firstFocused.node.id).hasClass("ui-menu-item");
		ashui.input.Keyboard.input(flTree, key(Named(ArrowDown), ArrowDown));
		flSettle();
		ashui.input.Keyboard.input(flTree, key(Named(Enter), Enter));
		ashui.input.Keyboard.input(flTree, key(Named(Enter), Enter, false));
		flSettle();
		var back = ashui.input.Focus.of(flTree) == m;
		check("a DropdownMenu opened by the keyboard focuses its first item; the arrows skip a disabled item; Enter chooses and closes it, focus back on the trigger",
			firstIsOne && picked.get() == "two" && !menuOpen.get() && back, [firstIsOne, picked.get(), menuOpen.get(), back]);

		// --- Toasts: shown, gone after their time, held while the pointer is on one, dismissed by their handle ---
		var toastTree = new LayoutTree();
		var toastRoot:Div = Owner.root(toastTree, _ -> hxx('<div width={720} height={420}><toaster /></div>'));
		function toastFrames(n:Int)
			for (_ in 0...n) {
				ashui.animation.AnimationScheduler.main.tick(1 / 60);
				toastTree.flush();
				toastTree.computeLayout(toastRoot.node, 720, 420);
				toastTree.flush();
			}
		function count()
			return @:privateAccess Toaster.current.toasts.get().length;
		toastFrames(1);
		Toaster.show({title: "Brief", duration: 0.2});
		var kept = Toaster.show({title: "Kept", duration: 0});
		toastFrames(2);
		var both = count() == 2;
		toastFrames(40);
		var afterTime = count();
		kept.dismiss();
		toastFrames(30);
		check("a toast goes after its time and when dismissed; one with no time stays until then", both && afterTime == 1 && count() == 0,
			[both, afterTime, count()]);

		// --- Forms: a checkbox's text checks it, a radio group's arrows choose, a select's placeholder, steppers that stop at the bounds ---
		var formTree = new LayoutTree();
		var agree = Signal.make(false), pick = Signal.make("a"), fruitPick = Signal.make(""), qty = Signal.make(1.0);
		var formRoot:Div = Owner.root(formTree, _ -> hxx('
			<div width={600} height={400} flexDirection={Column} gap={12} padding={10}>
				<checkbox id="agree" checked={agree}>I agree</checkbox>
				<radio-group value={pick}><radio-group-item id="ra" value="a">A</radio-group-item><radio-group-item value="b">B</radio-group-item></radio-group>
				<select id="fr" value={fruitPick} placeholder="Choose"><select-item value="apple">Apple</select-item></select>
				<number-input value={qty} min={0} max={2} />
			</div>
		'));
		function formSettle() {
			formTree.flush();
			formTree.computeLayout(formRoot.node, 600, 400);
			formTree.flush();
			formTree.computeLayout(formRoot.node, 600, 400);
		}
		function formFind(at:haxe.Int64, pred:ashui.css.Identity->Bool):Array<haxe.Int64> {
			var out = [];
			var identity = identity2(formTree, at);
			if (identity != null && pred(identity))
				out.push(at);
			for (c in formTree.children(at))
				out = out.concat(formFind(c, pred));
			return out;
		}
		function formClick(id:haxe.Int64) {
			var b = formTree.getBounds(new ashui.layout.Node(id));
			ashui.input.Pointer.move(formTree, b.x + b.width / 2, b.y + b.height / 2);
			ashui.input.Pointer.press(formTree);
			ashui.input.Pointer.release(formTree);
			formSettle();
		}
		formSettle();
		formClick(formFind(formRoot.node.id, i -> i.hasClass("ui-checkbox-text"))[0]);
		check("a press on a Checkbox's text checks it", agree.get());
		var dialA = formFind(formRoot.node.id, i -> i.id == "ra")[0];
		ashui.input.Focus.set(ashui.input.Interaction.byId(formTree, dialA), true);
		ashui.input.Keyboard.input(formTree, key(Named(ArrowDown), ArrowDown));
		formSettle();
		check("a RadioGroup's arrows move to the next item and choose it", pick.get() == "b", pick.get());
		var fr = formFind(formRoot.node.id, i -> i.id == "fr")[0];
		check("a Select with a placeholder keeps no value and says so", fruitPick.get() == "" && identity2(formTree, fr).attribute("data-placeholder") != null);
		var steps = formFind(formRoot.node.id, i -> i.hasClass("ui-number-step"));
		formClick(steps[1]);
		formClick(steps[1]);
		var top = qty.get();
		for (_ in 0...3)
			formClick(steps[0]);
		check("a NumberInput's buttons step it and stop at its bounds", top == 2 && qty.get() == 0, [top, qty.get()]);

		// --- Toggles, a sheet, a hover card and a context menu ---
		var pnTree = new LayoutTree();
		var one = Signal.make(["a"]), many = Signal.make(([] : Array<String>)), sheetOpen = Signal.make(false), ctxPick = Signal.make("");
		var pnRoot:Div = Owner.root(pnTree, _ -> hxx('
			<div width={800} height={500} flexDirection={Column} gap={12} padding={10}>
				<toggle-group value={one}><toggle-group-item id="ga" value="a">A</toggle-group-item><toggle-group-item id="gb" value="b">B</toggle-group-item></toggle-group>
				<toggle-group type="multiple" value={many}><toggle-group-item id="ma" value="a">A</toggle-group-item><toggle-group-item id="mb" value="b">B</toggle-group-item></toggle-group>
				<sheet open={sheetOpen}><sheet-trigger id="sh">Open</sheet-trigger><sheet-content side="left"><p>Hi</p></sheet-content></sheet>
				<hover-card openDelay={0.2}><hover-card-trigger id="hc"><p>@me</p></hover-card-trigger><hover-card-content><p>Card</p></hover-card-content></hover-card>
				<context-menu><context-menu-trigger id="ctx"><div width={200} height={80} /></context-menu-trigger>
					<context-menu-content><context-menu-item onSelect={() -> ctxPick.set("x")}>X</context-menu-item></context-menu-content></context-menu>
			</div>
		'));
		function pnFrames(n:Int)
			for (_ in 0...n) {
				ashui.animation.AnimationScheduler.main.tick(1 / 60);
				pnTree.flush();
				pnTree.computeLayout(pnRoot.node, 800, 500);
				pnTree.flush();
			}
		function pnAt(id:String, ?root:haxe.Int64):{x:Float, y:Float} {
			var found:Null<haxe.Int64> = null;
			function walk(at:haxe.Int64) {
				var identity = identity2(pnTree, at);
				if (identity != null && identity.id == id)
					found = at;
				for (c in pnTree.children(at))
					walk(c);
			}
			walk(root != null ? root : pnRoot.node.id);
			var b = pnTree.getBounds(new ashui.layout.Node(found));
			return {x: b.x + b.width / 2, y: b.y + b.height / 2};
		}
		function pnClick(id:String, ?button:window.MouseButton) {
			var p = pnAt(id);
			ashui.input.Pointer.move(pnTree, p.x, p.y);
			ashui.input.Pointer.press(pnTree, button == null ? Left : button);
			ashui.input.Pointer.release(pnTree, button == null ? Left : button);
			pnFrames(30);
		}
		pnFrames(2);
		pnClick("gb");
		var singleMoved = one.get().join(",") == "b";
		pnClick("gb");
		pnClick("ma");
		pnClick("mb");
		check("a single ToggleGroup moves its one choice and keeps it; a multiple one gathers them", singleMoved && one.get().join(",") == "b"
			&& many.get().join(",") == "a,b", [one.get(), many.get()]);

		pnClick("sh");
		var entry = ashui.ui.TopLayer.openEntries()[0];
		var sb2 = entry == null ? null : pnTree.getBounds(entry.content.node);
		var atLeft = sb2 != null && sb2.x > 0 && sb2.x <= 8.5 && sb2.height > 450;
		var closeBox = Lambda.find(pnTree.order(), id -> identity2(pnTree, id) != null && identity2(pnTree, id).hasClass("ui-sheet-close"));
		var cb = pnTree.getBounds(new ashui.layout.Node(closeBox));
		ashui.input.Pointer.move(pnTree, cb.x + cb.width / 2, cb.y + cb.height / 2);
		ashui.input.Pointer.press(pnTree);
		ashui.input.Pointer.release(pnTree);
		pnFrames(30);
		check("a Sheet opens floating just inside its edge, its full height less the inset, and its corner button closes it", sheetOpen.get() == false && atLeft, [atLeft, sheetOpen.get()]);

		var hp = pnAt("hc");
		ashui.input.Pointer.move(pnTree, hp.x, hp.y);
		pnFrames(6);
		var tooSoon = ashui.ui.TopLayer.openEntries().length;
		pnFrames(12);
		var opened2 = ashui.ui.TopLayer.openEntries().length;
		var card = ashui.ui.TopLayer.openEntries()[0].content;
		var cardBox = pnTree.getBounds(card.node);
		ashui.input.Pointer.move(pnTree, cardBox.x + 10, cardBox.y + 10);
		pnFrames(30);
		var stayed2 = ashui.ui.TopLayer.openEntries().length;
		ashui.input.Pointer.move(pnTree, 790, 490);
		pnFrames(40);
		check("a HoverCard opens after its delay, stays as the pointer moves onto the card, and closes once it leaves both",
			tooSoon == 0 && opened2 == 1 && stayed2 == 1 && ashui.ui.TopLayer.openEntries().length == 0, [tooSoon, opened2, stayed2]);

		var cp = pnAt("ctx");
		ashui.input.Pointer.move(pnTree, cp.x, cp.y);
		ashui.input.Pointer.press(pnTree, Right);
		ashui.input.Pointer.release(pnTree, Right);
		pnFrames(20);
		var menu = ashui.ui.TopLayer.openEntries()[0];
		var mb2 = menu == null ? null : pnTree.getBounds(menu.content.node);
		var atPointer = mb2 != null && Math.abs(mb2.x - cp.x) < 1 && Math.abs(mb2.y - cp.y) < 1;
		ashui.input.Pointer.move(pnTree, mb2.x + 20, mb2.y + 15);
		ashui.input.Pointer.press(pnTree);
		ashui.input.Pointer.release(pnTree);
		pnFrames(20);
		check("a right-click opens a ContextMenu with its corner at the pointer; an item chosen closes it", atPointer && ctxPick.get() == "x"
			&& ashui.ui.TopLayer.openEntries().length == 0, [atPointer, ctxPick.get()]);

		// --- Breadcrumb, pagination, table, kbd ---
		var dtTree = new LayoutTree();
		var pg = Signal.make(1);
		var dtRoot:Div = Owner.root(dtTree, _ -> hxx('
			<div width={800} height={500} flexDirection={Column} gap={12} padding={10}>
				<breadcrumb><breadcrumb-item>Home</breadcrumb-item><breadcrumb-item current={true}>Here</breadcrumb-item></breadcrumb>
				<pagination page={pg} total={10} />
				<table><table-body>
					<table-row><table-cell>A</table-cell><table-cell>B</table-cell></table-row>
					<table-row><table-cell>CC</table-cell><table-cell>D</table-cell></table-row>
				</table-body></table>
				<kbd>K</kbd>
			</div>
		'));
		function dtSettle() {
			dtTree.flush();
			dtTree.computeLayout(dtRoot.node, 800, 500);
			dtTree.flush();
			dtTree.computeLayout(dtRoot.node, 800, 500);
		}
		function dtAll(pred:ashui.css.Identity->Bool):Array<haxe.Int64>
			return [for (id in dtTree.order()) if (identity2(dtTree, id) != null && pred(identity2(dtTree, id))) id];
		function dtClick(id:haxe.Int64) {
			var b = dtTree.getBounds(new ashui.layout.Node(id));
			ashui.input.Pointer.move(dtTree, b.x + b.width / 2, b.y + b.height / 2);
			ashui.input.Pointer.press(dtTree);
			ashui.input.Pointer.release(dtTree);
			dtSettle();
		}
		dtSettle();
		var crumbs = dtAll(i -> i.hasClass("ui-breadcrumb-item")), seps = dtAll(i -> i.hasClass("ui-breadcrumb-separator"));
		check("a Breadcrumb puts a separator between its items and marks the current one", crumbs.length == 2 && seps.length == 1
			&& identity2(dtTree, crumbs[1]).attribute("data-current") == "page");
		var steps = dtAll(i -> i.hasClass("ui-pagination-button") && i.attribute("data-step") != null);
		var prevDisabled = ashui.input.Interaction.byId(dtTree, steps[0]).disabled.get();
		dtClick(steps[1]);
		var afterNext = pg.get();
		// On page 2 the numbers are 1, 2, 3 and 10.
		var numbers = dtAll(i -> i.hasClass("ui-pagination-button") && i.attribute("data-step") == null);
		dtClick(numbers[2]);
		var active = dtAll(i -> i.hasClass("ui-pagination-button") && i.attribute("data-state") == "active");
		check("Pagination follows its page: previous disabled on the first, next and a number step it, the current one active",
			prevDisabled && afterNext == 2 && pg.get() == 3 && active.length == 1, [prevDisabled, afterNext, pg.get(), active.length]);
		var cells = dtAll(i -> i.hasClass("ui-table-cell"));
		var c0 = dtTree.getBounds(new ashui.layout.Node(cells[1])), c1 = dtTree.getBounds(new ashui.layout.Node(cells[3]));
		check("a Table's rows share their columns", Math.abs(c0.x - c1.x) < 0.5, [c0.x, c1.x]);
		check("a Kbd is a kbd keycap", dtAll(i -> i.hasClass("ui-kbd") && i.types.indexOf("kbd") >= 0).length == 1);

		// --- Menubar and navigation menu ---
		var mbTree = new LayoutTree();
		var mbRoot:Div = Owner.root(mbTree, _ -> hxx('
			<div width={800} height={500} flexDirection={Column} gap={60} padding={10}>
				<menubar>
					<menubar-menu><menubar-trigger id="mf">File</menubar-trigger><menubar-content><menubar-item>New</menubar-item></menubar-content></menubar-menu>
					<menubar-menu><menubar-trigger id="me">Edit</menubar-trigger><menubar-content><menubar-item>Undo</menubar-item></menubar-content></menubar-menu>
				</menubar>
				<navigation-menu>
					<navigation-menu-item><navigation-menu-trigger id="na">A</navigation-menu-trigger><navigation-menu-content><navigation-menu-link>a</navigation-menu-link></navigation-menu-content></navigation-menu-item>
					<navigation-menu-item><navigation-menu-trigger id="nb">B</navigation-menu-trigger><navigation-menu-content><navigation-menu-link>b</navigation-menu-link></navigation-menu-content></navigation-menu-item>
				</navigation-menu>
			</div>
		'));
		function mbFrames(n:Int)
			for (_ in 0...n) {
				ashui.animation.AnimationScheduler.main.tick(1 / 60);
				mbTree.flush();
				mbTree.computeLayout(mbRoot.node, 800, 500);
				mbTree.flush();
			}
		function mbAt(id:String):{x:Float, y:Float} {
			var found:Null<haxe.Int64> = null;
			for (n in mbTree.order())
				if (identity2(mbTree, n) != null && identity2(mbTree, n).id == id)
					found = n;
			var b = mbTree.getBounds(new ashui.layout.Node(found));
			return {x: b.x + b.width / 2, y: b.y + b.height / 2};
		}
		function openLabel():Null<String> {
			var entries = ashui.ui.TopLayer.openEntries();
			if (entries.length == 0)
				return null;
			var b = mbTree.getBounds(entries[entries.length - 1].content.node);
			return b == null ? null : Std.string(Math.round(b.x));
		}
		mbFrames(2);
		var f = mbAt("mf"), e = mbAt("me");
		ashui.input.Pointer.move(mbTree, f.x, f.y);
		ashui.input.Pointer.press(mbTree);
		ashui.input.Pointer.release(mbTree);
		mbFrames(20);
		var fileMenuX = openLabel();
		ashui.input.Pointer.move(mbTree, e.x, e.y);
		mbFrames(20);
		var editMenuX = openLabel();
		ashui.input.Keyboard.input(mbTree, key(Named(ArrowLeft), ArrowLeft));
		mbFrames(20);
		var backX = openLabel();
		ashui.input.Keyboard.input(mbTree, key(Named(Escape), Escape));
		mbFrames(20);
		check("a Menubar: the pointer crossing to another trigger opens its menu in place, the arrows move between menus, each lined up with its trigger",
			fileMenuX != null && editMenuX != null && fileMenuX != editMenuX && backX == fileMenuX && ashui.ui.TopLayer.openEntries().length == 0,
			[fileMenuX, editMenuX, backX]);
		var na = mbAt("na"), nb = mbAt("nb");
		ashui.input.Pointer.move(mbTree, na.x, na.y);
		mbFrames(20);
		var oneOpen = ashui.ui.TopLayer.openEntries().length;
		ashui.input.Pointer.move(mbTree, nb.x, nb.y);
		mbFrames(30);
		var stillOne = ashui.ui.TopLayer.openEntries().length;
		ashui.input.Pointer.move(mbTree, 790, 490);
		mbFrames(40);
		check("a NavigationMenu opens an item resting on it, one at a time, and closes once the pointer leaves",
			oneOpen == 1 && stillOne == 1 && ashui.ui.TopLayer.openEntries().length == 0, [oneOpen, stillOne]);

		// --- ScrollArea: its scrollbar mode from CSS, the wheel scrolling it ---
		var saTree = new LayoutTree();
		var saRoot:Div = Owner.root(saTree, _ -> hxx('
			<div width={600} height={300} flexDirection={Row} gap={10}>
				<scroll-area height={100} width={120}><div height={400} /></scroll-area>
				<scroll-area height={100} width={120} scrollbars="always"><div height={400} /></scroll-area>
				<scroll-area height={100} width={120} scrollbars="hidden"><div height={400} /></scroll-area>
			</div>
		'));
		saTree.flush();
		saTree.computeLayout(saRoot.node, 600, 300);
		saTree.flush();
		saTree.computeLayout(saRoot.node, 600, 300);
		var areas = saTree.children(saRoot.node.id);
		var modes = [for (a in areas) {
			var sc = ashui.input.Scroll.at(a);
			sc == null ? "none" : sc.visibility;
		}];
		var first = ashui.input.Scroll.at(areas[0]);
		var ab = saTree.getBounds(new ashui.layout.Node(areas[0]));
		ashui.input.Pointer.move(saTree, ab.x + 10, ab.y + 10);
		@:privateAccess ashui.input.Pointer.wheel(saTree, 0, -60);
		check("a ScrollArea scrolls under the wheel; its scrollbars mode comes from the library's CSS", modes.join(",") == "auto,always,hidden"
			&& first != null && first.y.get() > 0, [modes, first == null ? -1 : first.y.get()]);

		// --- Command and Combobox ---
		var cmTree = new LayoutTree();
		var cmPick = Signal.make(""), cbValue = Signal.make("");
		var cmRoot:Div = Owner.root(cmTree, _ -> hxx('
			<div width={800} height={500} flexDirection={Row} gap={20} padding={10} alignItems={Start}>
				<command onSelect={v -> cmPick.set(v)}>
					<command-input id="q" />
					<command-list>
						<command-empty>None</command-empty>
						<command-group heading="A"><command-item value="apple">Apple</command-item><command-item value="apricot">Apricot</command-item></command-group>
						<command-group heading="B"><command-item value="banana">Banana</command-item></command-group>
					</command-list>
				</command>
				<combobox id="cb" value={cbValue} options={[{value: "x", label: "Ex"}, {value: "y", label: "Why"}]} />
			</div>
		'));
		function cmFrames(n:Int)
			for (_ in 0...n) {
				ashui.animation.AnimationScheduler.main.tick(1 / 60);
				cmTree.flush();
				cmTree.computeLayout(cmRoot.node, 800, 500);
				cmTree.flush();
			}
		function cmFind(pred:ashui.css.Identity->Bool):Array<haxe.Int64>
			return [for (id in cmTree.order()) if (identity2(cmTree, id) != null && pred(identity2(cmTree, id))) id];
		function cmPress(id:haxe.Int64) {
			var b = cmTree.getBounds(new ashui.layout.Node(id));
			ashui.input.Pointer.move(cmTree, b.x + b.width / 2, b.y + b.height / 2);
			ashui.input.Pointer.press(cmTree);
			ashui.input.Pointer.release(cmTree);
			cmFrames(20);
		}
		cmFrames(2);
		cmPress(cmFind(i -> i.id == "q")[0]);
		ashui.input.Keyboard.text(cmTree, "ap");
		cmFrames(3);
		var hiddenGroups = cmFind(i -> i.hasClass("ui-command-group") && i.attribute("data-hidden") != null).length;
		var emptyHidden = cmFind(i -> i.hasClass("ui-command-empty") && i.attribute("data-hidden") != null).length;
		ashui.input.Keyboard.input(cmTree, key(Named(ArrowDown), ArrowDown));
		ashui.input.Keyboard.input(cmTree, key(Named(Enter), Enter));
		cmFrames(2);
		ashui.input.Keyboard.text(cmTree, "zz");
		cmFrames(3);
		var emptyShown = cmFind(i -> i.hasClass("ui-command-empty") && i.attribute("data-hidden") == null).length;
		check("a Command filters as it is typed in, hiding a group with nothing left; the arrows and Enter choose; it says when nothing matches",
			hiddenGroups == 1 && emptyHidden == 1 && cmPick.get() == "apricot" && emptyShown == 1, [hiddenGroups, emptyHidden, cmPick.get(), emptyShown]);
		cmPress(cmFind(i -> i.id == "cb")[0]);
		ashui.input.Keyboard.text(cmTree, "why");
		cmFrames(3);
		ashui.input.Keyboard.input(cmTree, key(Named(Enter), Enter));
		cmFrames(20);
		check("a Combobox opens a search on its options and the one chosen is its value", cbValue.get() == "y" && ashui.ui.TopLayer.openEntries().length == 0,
			cbValue.get());

		// --- Calendar: a press chooses, the keys cross into the next month ---
		var calTree = new LayoutTree();
		var day = Signal.make((null : Null<ashui.components.Calendar.CalendarDay>));
		var calRoot:Div = Owner.root(calTree, _ -> hxx('<div width={400} height={400}><calendar value={day} today={{year: 2026, month: 9, day: 4}} /></div>'));
		function calFrames(n:Int)
			for (_ in 0...n) {
				ashui.animation.AnimationScheduler.main.tick(1 / 60);
				calTree.flush();
				calTree.computeLayout(calRoot.node, 400, 400);
				calTree.flush();
			}
		calFrames(2);
		var cells = [for (id in calTree.order()) if (identity2(calTree, id) != null && identity2(calTree, id).hasClass("ui-calendar-day")) id];
		var first = identity2(calTree, cells[0]);
		var cb2 = calTree.getBounds(new ashui.layout.Node(cells[33]));
		ashui.input.Pointer.move(calTree, cb2.x + cb2.width / 2, cb2.y + cb2.height / 2);
		ashui.input.Pointer.press(calTree);
		ashui.input.Pointer.release(calTree);
		calFrames(5);
		var pressed = day.get();
		ashui.input.Keyboard.input(calTree, key(Named(ArrowDown), ArrowDown));
		calFrames(5);
		function calGrids()
			return [for (id in calTree.order()) if (identity2(calTree, id) != null && identity2(calTree, id).hasClass("ui-calendar-grid")) identity2(calTree, id)];
		var turning = [for (g in calGrids()) '${g.attribute("data-enter")}/${g.attribute("data-leaving")}'].join(",");
		ashui.input.Keyboard.input(calTree, key(Named(Enter), Enter));
		ashui.input.Keyboard.input(calTree, key(Named(Enter), Enter, false));
		calFrames(5);
		var stepped = day.get();
		check("a Calendar shows six weeks from the month's first week, a press chooses a day, the arrows cross into the next month",
			first.attribute("data-outside") != null && pressed != null && pressed.month == 9 && pressed.day == 30 && stepped != null
			&& stepped.month == 10 && stepped.day == 6, [pressed, stepped]);
		calFrames(20);
		check("turning the month slides the next one in and the shown one out, which then goes", turning == "null/next,next/null" && calGrids().length == 1,
			[turning, calGrids().length]);
		function calendarPart(name:String):haxe.Int64
			return Lambda.find(calTree.order(), id -> identity2(calTree, id) != null && identity2(calTree, id).hasClass(name));
		function clickCalendarPart(name:String) {
			var b = calTree.getBounds(new ashui.layout.Node(calendarPart(name)));
			ashui.input.Pointer.move(calTree, b.x + b.width / 2, b.y + b.height / 2);
			ashui.input.Pointer.press(calTree);
			ashui.input.Pointer.release(calTree);
			calFrames(2);
		}
		var monthPickerId = calendarPart("ui-calendar-month-picker");
		var yearPickerId = calendarPart("ui-calendar-year-picker");
		var monthAfterNav = ashui.ui.Select.at(monthPickerId).value.get();
		var monthBounds = calTree.getBounds(new ashui.layout.Node(monthPickerId));
		var yearBounds = calTree.getBounds(new ashui.layout.Node(yearPickerId));
		clickCalendarPart("ui-calendar-month-picker");
		function calendarListbox():ashui.css.Identity
			return Lambda.find([for (id in calTree.order()) identity2(calTree, id)], i -> i != null && i.types.indexOf("listbox") >= 0);
		var monthListShadow = ashui.css.Css.computed(calendarListbox(), "box-shadow");
		var monthListPadding = ashui.css.Css.computed(calendarListbox(), "padding");
		ashui.input.Keyboard.input(calTree, key(Named(End), End));
		ashui.input.Keyboard.input(calTree, key(Named(Enter), Enter));
		calFrames(5);
		clickCalendarPart("ui-calendar-year-picker");
		var shownYearOptions = [for (id in calTree.order()) if (identity2(calTree, id) != null && identity2(calTree, id).types.indexOf("option") >= 0
			&& calTree.getBounds(new ashui.layout.Node(id)) != null && calTree.getBounds(new ashui.layout.Node(id)).height > 0) id];
		check("the Calendar year select lays out only the visible options", shownYearOptions.length > 0 && shownYearOptions.length < 20,
			shownYearOptions.length);
		check("the Calendar year list keeps the Select popup styling",
			ashui.css.Css.computed(calendarListbox(), "box-shadow") == monthListShadow
			&& ashui.css.Css.computed(calendarListbox(), "padding") == monthListPadding,
			[monthListShadow, ashui.css.Css.computed(calendarListbox(), "box-shadow"), monthListPadding,
				ashui.css.Css.computed(calendarListbox(), "padding")]);
		var yearList = calendarListbox();
		var yearListBounds = calTree.getBounds(yearList.node);
		ashui.input.Pointer.move(calTree, yearListBounds.x + yearListBounds.width / 2, yearListBounds.y + yearListBounds.height / 2);
		ashui.input.Pointer.wheel(calTree, 0, -165);
		calFrames(2);
		check("the Calendar year list scrolls its visible options", ashui.input.Scroll.at(yearList.node.id).y.get() > 0
			&& [for (id in calTree.order()) if (identity2(calTree, id) != null && identity2(calTree, id).types.indexOf("option") >= 0
				&& calTree.getBounds(new ashui.layout.Node(id)) != null && calTree.getBounds(new ashui.layout.Node(id)).height > 0) id].length < 20);
		ashui.input.Keyboard.text(calTree, "2124");
		ashui.input.Keyboard.input(calTree, key(Named(Enter), Enter));
		calFrames(5);
		check("the Calendar year Select keeps typeahead", ashui.ui.Select.at(yearPickerId).value.get() == "2124",
			ashui.ui.Select.at(yearPickerId).value.get());
		clickCalendarPart("ui-calendar-year-picker");
		ashui.input.Keyboard.input(calTree, key(Named(End), End));
		ashui.input.Keyboard.input(calTree, key(Named(Enter), Enter));
		calFrames(5);
		var chosenMonth = ashui.ui.Select.at(monthPickerId).value.get();
		var chosenYear = ashui.ui.Select.at(yearPickerId).value.get();
		check("Calendar month and year pickers turn the page without choosing a new day",
			monthBounds.width <= 107 && yearBounds.width <= 73 && monthAfterNav == "10" && chosenMonth == "11" && chosenYear == "2126" && day.get().year == 2026,
			[monthBounds.width, yearBounds.width, monthAfterNav, chosenMonth, chosenYear, day.get()]);
		// The next arrow takes December 2126 into 2127, beyond the initial year list.
		var nextNav = Lambda.find(calTree.order(), id -> identity2(calTree, id) != null && identity2(calTree, id).attribute("data-step") == "next");
		var nextBounds = calTree.getBounds(new ashui.layout.Node(nextNav));
		ashui.input.Pointer.move(calTree, nextBounds.x + nextBounds.width / 2, nextBounds.y + nextBounds.height / 2);
		ashui.input.Pointer.press(calTree);
		ashui.input.Pointer.release(calTree);
		calFrames(5);
		var recenteredYear = ashui.ui.Select.at(calendarPart("ui-calendar-year-picker")).value.get();
		check("the Calendar year picker recentres beyond its initial range", recenteredYear == "2127", recenteredYear);

		var limitedTree = new LayoutTree();
		var limitedValue = Signal.make((null : Null<ashui.components.Calendar.CalendarDay>));
		var limitedRoot:Div = Owner.root(limitedTree, _ -> hxx('<div width={400} height={400}><calendar value={limitedValue} today={{year: 2022, month: 0, day: 1}} minYear={2024} maxYear={2026} /></div>'));
		function limitedFrames(n:Int)
			for (_ in 0...n) {
				limitedTree.flush();
				limitedTree.computeLayout(limitedRoot.node, 400, 400);
				limitedTree.flush();
			}
		function limitedPart(name:String, ?step:String):haxe.Int64
			return Lambda.find(limitedTree.order(), id -> {
				var i = identity2(limitedTree, id);
				return i != null && i.hasClass(name) && (step == null || i.attribute("data-step") == step);
			});
		function limitedClick(id:haxe.Int64) {
			var b = limitedTree.getBounds(new ashui.layout.Node(id));
			ashui.input.Pointer.move(limitedTree, b.x + b.width / 2, b.y + b.height / 2);
			ashui.input.Pointer.press(limitedTree);
			ashui.input.Pointer.release(limitedTree);
			limitedFrames(2);
		}
		limitedFrames(2);
		var limitedYear = limitedPart("ui-calendar-year-picker");
		var limitedMonth = limitedPart("ui-calendar-month-picker");
		var earliest = ashui.ui.Select.at(limitedYear).value.get() == "2024" && ashui.ui.Select.at(limitedMonth).value.get() == "0";
		var prev = limitedPart("ui-calendar-nav", "prev");
		var outsideDay = Lambda.find(limitedTree.order(), id -> {
			var i = identity2(limitedTree, id);
			return i != null && i.hasClass("ui-calendar-day") && i.attribute("data-outside") != null;
		});
		var lowerDisabled = ashui.input.Interaction.byId(limitedTree, prev).disabled.get()
			&& ashui.input.Interaction.byId(limitedTree, outsideDay).disabled.get();
		limitedClick(prev);
		check("Calendar minYear clamps the initial view and blocks earlier dates",
			earliest && lowerDisabled && ashui.ui.Select.at(limitedYear).value.get() == "2024" && limitedValue.get() == null,
			[earliest, lowerDisabled, ashui.ui.Select.at(limitedYear).value.get(), limitedValue.get()]);
		limitedClick(limitedYear);
		var yearOptionCount = [for (id in limitedTree.order()) if (identity2(limitedTree, id) != null
			&& identity2(limitedTree, id).hasClass("ui-select-item")) id].length;
		check("Calendar year options stop at its configured bounds", yearOptionCount == 3, yearOptionCount);
		ashui.input.Keyboard.input(limitedTree, key(Named(End), End));
		ashui.input.Keyboard.input(limitedTree, key(Named(Enter), Enter));
		limitedFrames(3);
		limitedClick(limitedMonth);
		ashui.input.Keyboard.input(limitedTree, key(Named(End), End));
		ashui.input.Keyboard.input(limitedTree, key(Named(Enter), Enter));
		limitedFrames(3);
		var next = limitedPart("ui-calendar-nav", "next");
		var upperDisabled = ashui.input.Interaction.byId(limitedTree, next).disabled.get();
		limitedClick(next);
		check("Calendar maxYear ends its picker and blocks navigation past December",
			upperDisabled && ashui.ui.Select.at(limitedYear).value.get() == "2026" && ashui.ui.Select.at(limitedMonth).value.get() == "11",
			[upperDisabled, ashui.ui.Select.at(limitedYear).value.get(), ashui.ui.Select.at(limitedMonth).value.get()]);

		// --- Charts: the tooltip shows the values at the label under the pointer; new values are moved to, not jumped to ---
		var chTree = new LayoutTree();
		var chData = Signal.make(([{name: "Desktop", values: [10.0, 30, 20]}, {name: "Mobile", values: [5.0, 15, 25]}] : Array<ChartSeries>));
		var chRoot:Div = Owner.root(chTree, _ -> hxx('<div width={400} height={300} padding={20}><line-chart series={chData} labels={["Jan", "Feb", "Mar"]} /></div>'));
		function chFrames(n:Int)
			for (_ in 0...n) {
				ashui.animation.AnimationScheduler.main.tick(1 / 60);
				chTree.flush();
				chTree.computeLayout(chRoot.node, 400, 300);
				chTree.flush();
			}
		function chFind(cls:String):Array<haxe.Int64>
			return [for (id in chTree.order()) if (identity2(chTree, id) != null && identity2(chTree, id).hasClass(cls)) id];
		function chText(id:haxe.Int64):String {
			var out = [];
			function walk(n:haxe.Int64) {
				var t = ashui.ui.Text.at(n);
				if (t != null)
					out.push(t.text());
				for (c in chTree.children(n))
					walk(c);
			}
			walk(id);
			return out.join("|");
		}
		chFrames(60);
		var plotBox = chTree.getBounds(new ashui.layout.Node(chFind("ui-chart-plot")[0]));
		var tipShown = () -> chTree.getBounds(new ashui.layout.Node(chFind("ui-chart-tooltip")[0])).width > 0;
		var hiddenBefore = !tipShown();
		// The middle third of the plot, past the value axis's labels: Feb.
		ashui.input.Pointer.move(chTree, plotBox.x + plotBox.width * 0.55, plotBox.y + plotBox.height / 2);
		chFrames(2);
		var tipText = chText(chFind("ui-chart-tooltip")[0]);
		check("a chart's tooltip shows the label under the pointer and each series' value there", hiddenBefore && tipShown()
			&& tipText == "Feb|Desktop|30|Mobile|15", [hiddenBefore, tipShown(), tipText]);
		ashui.input.Pointer.move(chTree, 5, 5);
		chFrames(2);
		check("and goes when the pointer leaves", !tipShown());
		var legend = [for (id in chFind("ui-chart-legend-item")) chText(id)].join(",");
		check("a chart of more than one series has a legend of their names", legend == "Desktop,Mobile", legend);

		// --- Pie chart: the slice under the pointer, by its angle, its label, value and share in the tooltip ---
		var pieTree = new LayoutTree();
		var pieRoot:Div = Owner.root(pieTree, _ -> hxx('<div width={300} height={300}><pie-chart slices={[{label: "A", value: 3.0}, {label: "B", value: 1.0}]} height={200} legend={false} /></div>'));
		for (_ in 0...60) {
			ashui.animation.AnimationScheduler.main.tick(1 / 60);
			pieTree.flush();
			pieTree.computeLayout(pieRoot.node, 300, 300);
			pieTree.flush();
		}
		var piePlot = Lambda.find(pieTree.order(), n -> identity2(pieTree, n) != null && identity2(pieTree, n).hasClass("ui-chart-plot"));
		var pb = pieTree.getBounds(new ashui.layout.Node(piePlot));
		// A, three quarters from the top clockwise, holds the right side; B, the last quarter, the upper left.
		ashui.input.Pointer.move(pieTree, pb.x + pb.width * 0.8, pb.y + pb.height * 0.5);
		pieTree.flush();
		var pieTip = Lambda.find(pieTree.order(), n -> identity2(pieTree, n) != null && identity2(pieTree, n).hasClass("ui-chart-tooltip-value"));
		var tipA = ashui.ui.Text.at(pieTree.children(pieTip)[0]).text();
		ashui.input.Pointer.move(pieTree, pb.x + pb.width * 0.3, pb.y + pb.height * 0.3);
		pieTree.flush();
		var tipB = ashui.ui.Text.at(pieTree.children(pieTip)[0]).text();
		check("a pie chart's tooltip names the slice under the pointer, its value and share", tipA == "3 · 75%" && tipB == "1 · 25%", [tipA, tipB]);

		// --- ref= on a component holds the component itself, typed as its class ---
		var cardRef = new ashui.ui.Ref<Card>();
		var refTree = new LayoutTree();
		Owner.root(refTree, _ -> hxx('<div><card ref={cardRef} width={120}><card-content>Hi</card-content></card></div>'));
		refTree.flush();
		check("ref= on a component holds the component", cardRef.get() != null && Std.isOfType(cardRef.get(), Card));

		// --- Sidebar: collapsing eases its width, the inset moving with it, its items kept on one line ---
		var sbTree = new LayoutTree();
		var folded = Signal.make(false);
		var sbRoot:Div = Owner.root(sbTree, _ -> hxx('
			<div width={700} height={400} flexDirection={Column}>
				<sidebar-layout height={300}>
					<sidebar collapsed={folded}><sidebar-item active={true}>Dashboard</sidebar-item><sidebar-group label="MORE"><sidebar-item>Settings</sidebar-item></sidebar-group></sidebar>
					<sidebar-inset><div height={20} /></sidebar-inset>
				</sidebar-layout>
			</div>
		'));
		function sbFrames(n:Int)
			for (_ in 0...n) {
				ashui.animation.AnimationScheduler.main.tick(1 / 60);
				sbTree.flush();
				sbTree.computeLayout(sbRoot.node, 700, 400);
				sbTree.flush();
			}
		function sbFind(cls:String):Array<haxe.Int64>
			return [for (id in sbTree.order()) if (identity2(sbTree, id) != null && identity2(sbTree, id).hasClass(cls)) id];
		function sbBox(id:haxe.Int64)
			return sbTree.getBounds(new ashui.layout.Node(id));
		sbFrames(2);
		var bar = sbFind("ui-sidebar")[0], inset = sbFind("ui-sidebar-inset")[0], item = sbFind("ui-sidebar-item")[0];
		var wide = sbBox(bar).width, itemHigh = sbBox(item).height;
		folded.set(true);
		sbFrames(6);
		var midway = sbBox(bar).width, insetMidway = sbBox(inset).x, itemMidway = sbBox(item).height;
		sbFrames(30);
		var narrow = sbBox(bar).width;
		check("a Sidebar collapses to its icons, its width easing and the inset moving with it, its items kept on one line, its state on data-state",
			narrow < midway && midway < wide && insetMidway < sbBox(bar).x + wide && itemMidway == itemHigh
			&& identity2(sbTree, bar).attribute("data-state") == "collapsed", [wide, midway, narrow, itemHigh, itemMidway]);


		// --- AspectRatio, AvatarGroup, InputOtp ---
		var exTree = new LayoutTree();
		var otpCode = Signal.make("");
		var otpDone = Signal.make("");
		var exRoot:Div = Owner.root(exTree, _ -> hxx('
			<div width={600} height={400} flexDirection={Column} gap={10}>
				<div width={160} flexDirection={Row}><aspect-ratio id="ar"><div /></aspect-ratio></div>
				<div width={90}><aspect-ratio id="sq" ratio={1}><div /></aspect-ratio></div>
				<div flexDirection={Row}>
					<avatar-group id="ag" max={2}><avatar><avatar-fallback>A</avatar-fallback></avatar><avatar><avatar-fallback>B</avatar-fallback></avatar><avatar><avatar-fallback>C</avatar-fallback></avatar><avatar><avatar-fallback>D</avatar-fallback></avatar></avatar-group>
					<div id="after" width={10} height={10} />
				</div>
				<input-otp id="otp" length={4} value={otpCode} onComplete={c -> otpDone.set(c)} />
			</div>
		'));
		function exFrames(n:Int)
			for (_ in 0...n) {
				ashui.animation.AnimationScheduler.main.tick(1 / 60);
				exTree.flush();
				exTree.computeLayout(exRoot.node, 600, 400);
				exTree.flush();
			}
		function exFind(pred:ashui.css.Identity->Bool):Array<haxe.Int64>
			return [for (id in exTree.order()) if (identity2(exTree, id) != null && pred(identity2(exTree, id))) id];
		function exBounds(name:String)
			return exTree.getBounds(new ashui.layout.Node(exFind(i -> i.id == name)[0]));
		exFrames(2);
		var ar = exBounds("ar"), sq = exBounds("sq");
		check("an AspectRatio is as wide as its container and as tall as its ratio makes it, 16 / 9 by default",
			ar.width == 160 && Math.abs(ar.height - 90) < 1 && sq.width == 90 && Math.abs(sq.height - 90) < 1, [ar.width, ar.height, sq.width, sq.height]);
		var ag = exBounds("ag"), after = exBounds("after");
		var more = exFind(i -> i.hasClass("ui-avatar-more"));
		check("an AvatarGroup overlaps its avatars, as wide as they are together, and counts past max in a bubble",
			more.length == 1 && exFind(i -> i.hasClass("ui-avatar")).length == 2 && ag.width == 100 && after.x == ag.x + ag.width,
			[more.length, ag.width, after.x]);
		var otpBox = exBounds("otp");
		ashui.input.Pointer.move(exTree, otpBox.x + 10, otpBox.y + otpBox.height / 2);
		ashui.input.Pointer.press(exTree);
		ashui.input.Pointer.release(exTree);
		exFrames(2);
		var activeFirst = exFind(i -> i.hasClass("ui-input-otp-slot") && i.attribute("data-active") != null).length;
		ashui.input.Keyboard.text(exTree, "1a2");
		exFrames(2);
		var partial = otpCode.get(), filled = exFind(i -> i.hasClass("ui-input-otp-slot") && i.attribute("data-filled") != null).length;
		ashui.input.Keyboard.text(exTree, "345");
		exFrames(2);
		check("an InputOtp keeps digits up to its length, marks the slots filled and the next active, and calls onComplete once full",
			activeFirst == 1 && partial == "12" && filled == 2 && otpCode.get() == "1234" && otpDone.get() == "1234",
			[activeFirst, partial, filled, otpCode.get(), otpDone.get()]);


		// --- Resizable: a handle drags the space between two panels within their bounds; its keys step it ---
		var rzTree = new LayoutTree();
		var rzLeft = Signal.make(150.0);
		var rzRoot:Div = Owner.root(rzTree, _ -> hxx('
			<div width={600} height={400} flexDirection={Column}>
				<resizable height={200}>
					<resizable-panel size={rzLeft} minSize={100} maxSize={300}><div /></resizable-panel>
					<resizable-panel id="mid" minSize={60}><div /></resizable-panel>
					<resizable-panel id="end"><div /></resizable-panel>
				</resizable>
			</div>
		'));
		function rzFrames(n:Int)
			for (_ in 0...n) {
				ashui.animation.AnimationScheduler.main.tick(1 / 60);
				rzTree.flush();
				rzTree.computeLayout(rzRoot.node, 600, 400);
				rzTree.flush();
			}
		function rzFind(pred:ashui.css.Identity->Bool):Array<haxe.Int64>
			return [for (id in rzTree.order()) if (identity2(rzTree, id) != null && pred(identity2(rzTree, id))) id];
		function rzBounds(id:haxe.Int64)
			return rzTree.getBounds(new ashui.layout.Node(id));
		rzFrames(2);
		var rzHandles = rzFind(i -> i.hasClass("ui-resizable-handle"));
		var h0 = rzBounds(rzHandles[0]);
		var hcx = h0.x + h0.width / 2, hcy = h0.y + h0.height / 2;
		ashui.input.Pointer.move(rzTree, hcx, hcy);
		ashui.input.Pointer.press(rzTree);
		rzFrames(1);
		var draggingSet = identity2(rzTree, rzHandles[0]).attribute("data-dragging") != null;
		ashui.input.Pointer.move(rzTree, hcx + 80, hcy);
		rzFrames(1);
		var dragged = rzLeft.get();
		ashui.input.Pointer.move(rzTree, hcx + 400, hcy);
		rzFrames(1);
		var atMax = rzLeft.get();
		ashui.input.Pointer.move(rzTree, hcx - 400, hcy);
		rzFrames(1);
		var atMin = rzLeft.get(), leftWidth = rzBounds(rzFind(i -> i.hasClass("ui-resizable-panel"))[0]).width;
		ashui.input.Pointer.release(rzTree);
		rzFrames(1);
		check("a Resizable handle drags its panel's size, kept within its min and max, marked while it drags",
			draggingSet && dragged == 230 && atMax == 300 && atMin == 100 && leftWidth == 100
			&& identity2(rzTree, rzHandles[0]).attribute("data-dragging") == null, [draggingSet, dragged, atMax, atMin, leftWidth]);
		ashui.input.Keyboard.input(rzTree, key(Named(ArrowRight), ArrowRight));
		ashui.input.Keyboard.input(rzTree, key(Named(ArrowRight), ArrowRight));
		var stepped = rzLeft.get();
		ashui.input.Keyboard.input(rzTree, key(Named(End), End));
		rzFrames(1);
		check("a focused Resizable handle steps by its arrow keys, and End takes it as far as the panels allow", stepped == 120 && rzLeft.get() == 300,
			[stepped, rzLeft.get()]);
		// The middle panel took a size when the first handle moved; the last, still sharing the space, takes what the middle gives up.
		var h1 = rzBounds(rzHandles[1]);
		var mid = rzFind(i -> i.id == "mid")[0], end = rzFind(i -> i.id == "end")[0];
		var midBefore = rzBounds(mid).width, endBefore = rzBounds(end).width;
		ashui.input.Pointer.move(rzTree, h1.x + h1.width / 2, h1.y + 20);
		ashui.input.Pointer.press(rzTree);
		ashui.input.Pointer.move(rzTree, h1.x + h1.width / 2 - 200, h1.y + 20);
		rzFrames(1);
		ashui.input.Pointer.release(rzTree);
		var midAfter = rzBounds(mid).width, endAfter = rzBounds(end).width;
		check("a Resizable handle gives a panel's space to the one beyond it, down to the panel's min, the last still filling the group",
			midAfter == 60 && Math.abs(endAfter - (endBefore + midBefore - 60)) <= 1, [midBefore, endBefore, midAfter, endAfter]);


		// --- Drawer: a short pull springs back, a long one or a flick closes it; its controls keep their presses ---
		var drTree = new LayoutTree();
		// A window sets the viewport its drawer's height is kept within.
		ashui.css.Css.setViewport(800, 600);
		var drOpen = Signal.make(false), drPressed = Signal.make(0);
		var drRoot:Div = Owner.root(drTree, _ -> hxx('
			<div width={800} height={600} flexDirection={Column}>
				<drawer open={drOpen}>
					<drawer-trigger id="drOpen">Open</drawer-trigger>
					<drawer-content>
						<drawer-header><drawer-title>Goal</drawer-title></drawer-header>
						<button id="drButton" onClick={_ -> drPressed.set(drPressed.get() + 1)}>Go</button>
					</drawer-content>
				</drawer>
			</div>
		'));
		function drFrames(n:Int)
			for (_ in 0...n) {
				ashui.animation.AnimationScheduler.main.tick(1 / 60);
				drTree.flush();
				drTree.computeLayout(drRoot.node, 800, 600);
				drTree.flush();
			}
		function drFind(pred:ashui.css.Identity->Bool):Null<haxe.Int64>
			return Lambda.find(drTree.order(), id -> identity2(drTree, id) != null && pred(identity2(drTree, id)) && drTree.getBounds(new ashui.layout.Node(id)) != null);
		function drCentre(id:haxe.Int64) {
			var b = drTree.getBounds(new ashui.layout.Node(id));
			return {x: b.x + b.width / 2, y: b.y + b.height / 2};
		}
		// Pulls the handle down by `by` over `steps` frames and lets go.
		function drPull(by:Float, steps:Int) {
			var c = drCentre(drFind(i -> i.hasClass("ui-drawer-handle")));
			ashui.input.Pointer.move(drTree, c.x, c.y);
			ashui.input.Pointer.press(drTree);
			for (k in 1...steps + 1) {
				drFrames(1);
				ashui.input.Pointer.move(drTree, c.x, c.y + by * k / steps);
			}
			drFrames(1);
			ashui.input.Pointer.release(drTree);
		}
		function drPanelTop():Float
			return drTree.getBounds(new ashui.layout.Node(drFind(i -> i.hasClass("ui-drawer")))).y;
		drFrames(2);
		var dc = drCentre(drFind(i -> i.id == "drOpen"));
		ashui.input.Pointer.move(drTree, dc.x, dc.y);
		ashui.input.Pointer.press(drTree);
		ashui.input.Pointer.release(drTree);
		drFrames(40);
		var restTop = drPanelTop();
		var drTrace = ashui.debug.MotionTrace.start();
		var c0 = drCentre(drFind(i -> i.hasClass("ui-drawer-handle")));
		ashui.input.Pointer.move(drTree, c0.x, c0.y);
		ashui.input.Pointer.press(drTree);
		ashui.input.Pointer.move(drTree, c0.x, c0.y + 30);
		drFrames(1);
		var whileDragging = identity2(drTree, drFind(i -> i.hasClass("ui-drawer"))).attribute("data-dragging") != null;
		ashui.input.Pointer.release(drTree);
		drFrames(60);
		drTrace.stop();
		var springs = [for (t in drTrace.tracks) if (t.kind == Spring) t];
		check("a Drawer pulled a little is marked dragging, and let go it springs back from where it was", drOpen.get() && whileDragging
			&& springs.length == 1 && springs[0].from == "30" && springs[0].to == "0" && springs[0].end == Completed,
			[for (t in springs) '${t.from}->${t.to} ${t.end}']);
		var bc = drCentre(drFind(i -> i.id == "drButton"));
		ashui.input.Pointer.move(drTree, bc.x, bc.y);
		ashui.input.Pointer.press(drTree);
		ashui.input.Pointer.move(drTree, bc.x, bc.y + 200);
		drFrames(1);
		var heldTop = drPanelTop();
		ashui.input.Pointer.move(drTree, bc.x, bc.y);
		ashui.input.Pointer.release(drTree);
		drFrames(2);
		check("a press on a Drawer's control does not drag it, and the control is clicked", heldTop == restTop && drPressed.get() == 1 && drOpen.get(),
			[heldTop, restTop, drPressed.get()]);
		drPull(400, 20);
		drFrames(40);
		check("a Drawer pulled past a third of its height closes", !drOpen.get(), drOpen.get());
		ashui.input.Pointer.move(drTree, dc.x, dc.y);
		ashui.input.Pointer.press(drTree);
		ashui.input.Pointer.release(drTree);
		drFrames(40);
		drPull(36, 2);
		drFrames(40);
		check("a Drawer flicked toward its edge closes, though it went only a little way", !drOpen.get(), drOpen.get());


		// --- TreeView: a press chooses and opens, the group grows in; the arrows walk the rows shown, Left steps out and closes ---
		var tvTree = new LayoutTree();
		var tvPick = Signal.make((null : Null<String>));
		var tvRoot:Div = Owner.root(tvTree, _ -> hxx('
			<div width={400} height={400} flexDirection={Column}>
				<tree-view selected={tvPick}>
					<tree-item id="tvA" value="a" label="A">
						<tree-item value="a1" label="A1" />
						<tree-item value="a2" label="A2" />
					</tree-item>
					<tree-item id="tvB" value="b" label="B" />
				</tree-view>
			</div>
		'));
		function tvFrames(n:Int)
			for (_ in 0...n) {
				ashui.animation.AnimationScheduler.main.tick(1 / 60);
				tvTree.flush();
				tvTree.computeLayout(tvRoot.node, 400, 400);
				tvTree.flush();
			}
		function tvItem(id:String):haxe.Int64
			return Lambda.find(tvTree.order(), n -> identity2(tvTree, n) != null && identity2(tvTree, n).id == id);
		function tvRowY(id:String):Float
			return tvTree.getBounds(new ashui.layout.Node(tvTree.children(tvItem(id))[0])).y;
		tvFrames(2);
		var bClosed = tvRowY("tvB");
		var aRow = tvTree.getBounds(new ashui.layout.Node(tvTree.children(tvItem("tvA"))[0]));
		ashui.input.Pointer.move(tvTree, aRow.x + 20, aRow.y + aRow.height / 2);
		ashui.input.Pointer.press(tvTree);
		ashui.input.Pointer.release(tvTree);
		tvFrames(1);
		var tvAnims:Map<String, ashui.animation.LayoutAnimation> = @:privateAccess ashui.animation.LayoutAnimation.animated.get(tvTree);
		var bMoving = @:privateAccess tvAnims.get(haxe.Int64.toStr(tvItem("tvB"))).running;
		tvFrames(40);
		var bOpen = tvRowY("tvB");
		check("a TreeView row pressed is chosen and opens, the rows below easing down as its items grow in",
			tvPick.get() == "a" && identity2(tvTree, tvItem("tvA")).attribute("data-state") == "open" && bMoving && bOpen - bClosed > 50,
			[tvPick.get(), bClosed, bMoving, bOpen]);
		ashui.input.Keyboard.input(tvTree, key(Named(ArrowDown), ArrowDown));
		ashui.input.Keyboard.input(tvTree, key(Named(ArrowDown), ArrowDown));
		ashui.input.Keyboard.input(tvTree, key(Named(Enter), Enter));
		var walked = tvPick.get();
		ashui.input.Keyboard.input(tvTree, key(Named(ArrowLeft), ArrowLeft));
		ashui.input.Keyboard.input(tvTree, key(Named(ArrowLeft), ArrowLeft));
		tvFrames(40);
		check("a TreeView's arrows walk the rows shown and Enter chooses; Left steps out to the parent, then closes it",
			walked == "a2" && identity2(tvTree, tvItem("tvA")).attribute("data-state") == "closed" && Math.abs(tvRowY("tvB") - bClosed) < 0.5,
			[walked, identity2(tvTree, tvItem("tvA")).attribute("data-state"), tvRowY("tvB")]);


		// --- Typography: prose spaces its elements by what follows what; lead, large and muted are their own text styles ---
		var tyTree = new LayoutTree();
		var tyRoot:Div = Owner.root(tyTree, _ -> hxx('
			<div width={800} height={800} flexDirection={Column}>
				<prose><h1 id="tyH1">Title</h1><p id="tyP1">First.</p><h2 id="tyH2">Section</h2><p id="tyP2">Second.</p></prose>
				<lead id="tyLead">Lead</lead><large id="tyLarge">Large</large><muted id="tyMuted">Muted</muted>
			</div>
		'));
		tyTree.flush();
		tyTree.computeLayout(tyRoot.node, 800, 800);
		tyTree.flush();
		function tyBox(id:String)
			return tyTree.getBounds(new ashui.layout.Node(Lambda.find(tyTree.order(), n -> identity2(tyTree, n) != null && identity2(tyTree, n).id == id)));
		var h1 = tyBox("tyH1"), p1 = tyBox("tyP1"), h2 = tyBox("tyH2"), p2 = tyBox("tyP2");
		var afterTitle = p1.y - (h1.y + h1.height), beforeSection = h2.y - (p1.y + p1.height), afterSection = p2.y - (h2.y + h2.height);
		check("Prose spaces a title's paragraph by 16, a section by 40 above and 24 below, its first element flush",
			h1.y == 0 && Math.abs(afterTitle - 16) < 0.5 && Math.abs(beforeSection - 40) < 0.5 && Math.abs(afterSection - 24) < 0.5,
			[h1.y, afterTitle, beforeSection, afterSection]);
		check("Lead, Large and Muted step the text size: larger, a little larger, smaller",
			tyBox("tyLead").height > tyBox("tyLarge").height && tyBox("tyLarge").height > tyBox("tyMuted").height,
			[tyBox("tyLead").height, tyBox("tyLarge").height, tyBox("tyMuted").height]);

		canvasKit();
		gltf();
		gltfTextureCap();
		canvasKit2D();

		// A labelled slider is 300 wide by default, and no wider than what holds it.
		var narrowTree = new LayoutTree();
		var narrowSlider:Null<Slider> = null;
		var narrow:Div = Owner.root(narrowTree, _ -> {
			narrowSlider = new Slider({label: "Exposure", value: 0.5});
			new Div({width: 200, flexDirection: Column, padding: 10}, [narrowSlider], narrowTree);
		});
		narrowTree.flush();
		narrowTree.computeLayout(narrow.node, 400, 200);
		var sb = narrowTree.getBounds(narrowSlider.node);
		check("a labelled slider in a column narrower than it shrinks to fit", sb != null && sb.width <= 180 + 0.5, sb == null ? null : sb.width);

		// A vertical slider retains the range's drag and keys, including a press on its HXX icon child.
		var verticalTree = new LayoutTree();
		var verticalValue = Signal.make(25.0);
		var verticalRoot:Div = Owner.root(verticalTree, _ -> <div width={200} height={200}>
			<slider id="verticalRange" value={verticalValue} min={0} max={100} step={1} orientation="vertical" width={24} height={160}>
				<div class="absolute" left={8} bottom={8} width={8} height={8}>
					<svg width={8} height={8} viewBox="0 0 8 8"><circle cx="4" cy="4" r="4" fill="currentColor" /></svg>
				</div>
			</slider>
		</div>);
		verticalTree.flush();
		verticalTree.computeLayout(verticalRoot.node, 200, 200);
		var verticalId = Lambda.find(verticalTree.order(), n -> identity2(verticalTree, n).id == "verticalRange");
		var verticalNode = new ashui.layout.Node(verticalId);
		var verticalParts = verticalTree.children(verticalId);
		var vb = verticalTree.getBounds(verticalNode);
		var vf = verticalTree.getBounds(new ashui.layout.Node(verticalParts[0]));
		var vt = verticalTree.getBounds(new ashui.layout.Node(verticalParts[1]));
		var vi = verticalTree.getBounds(new ashui.layout.Node(verticalParts[3]));
		check("a vertical slider fills from the bottom and retains its HXX content",
			identity2(verticalTree, verticalId).attribute("data-orientation") == "vertical" && verticalParts.length == 4
			&& Math.abs(vf.height - (vb.height - vt.height) * 0.25) < 0.5
			&& Math.abs(vf.y + vf.height - vb.y - vb.height) < 0.5, [vb, vf]);
		ashui.input.Pointer.move(verticalTree, vi.x + vi.width / 2, vi.y + vi.height / 2);
		ashui.input.Pointer.press(verticalTree);
		var iconPress = verticalValue.get();
		var iconExpected = Math.round((vb.y + vb.height - vi.y - vi.height / 2 - vt.height / 2) / (vb.height - vt.height) * 100);
		ashui.input.Pointer.move(verticalTree, vb.x + 200, vb.y + vb.height - vt.height / 2 - (vb.height - vt.height) * 0.75);
		var verticalDrag = verticalValue.get();
		ashui.input.Pointer.release(verticalTree);
		ashui.input.Pointer.move(verticalTree, vb.x + vb.width / 2, vb.y + vt.height / 2);
		check("a vertical slider can start on its icon, drag sideways out of its bounds, and stop on release",
			iconPress == iconExpected && verticalDrag == 75 && verticalValue.get() == 75, [iconPress, iconExpected, verticalDrag]);
		ashui.input.Keyboard.input(verticalTree, key(Named(ArrowUp), ArrowUp));
		var increased = verticalValue.get();
		ashui.input.Keyboard.input(verticalTree, key(Named(End), End));
		var atTop = verticalValue.get();
		ashui.input.Keyboard.input(verticalTree, key(Named(Home), Home));
		check("a vertical slider keeps Arrow Up, End and Home",
			increased == 76 && atTop == 100 && verticalValue.get() == 0, [increased, atTop, verticalValue.get()]);

		Sys.println(failures == 0 ? "ALL PASSED" : '$failures FAILED');
		Sys.exit(failures == 0 ? 0 : 1);
	}
}
