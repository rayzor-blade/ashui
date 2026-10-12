import ashui.canvaskit.Geometry;
import ashui.canvaskit.OrbitCamera;
import ashui.canvaskit.SceneGizmos;
import ashui.canvaskit.SceneKit;
import ashui.canvaskit.Selection3D;
import ashui.core.render.Offscreen;
import ashui.draw3d.Material;
import ashui.input.Keyboard;
import ashui.input.Pointer;
import ashui.layout.LayoutTree;
import ashui.math.Mat4;
import ashui.math.Quat;
import ashui.math.Vec3;
import ashui.reactive.Owner;
import ashui.reactive.Signal;
import ashui.types.Style;
import ashui.ui.Div;
import ashui.ui.Ref;
import gpu.GpuTextureViewDescriptor;

/** Gizmo GPU and real pointer arbitration checks (git-bug c16e24c). **/
class SceneGizmoPixels {
	static function check(name:String, ok:Bool) {
		if (!ok) throw name;
		Sys.println('ok   $name');
	}
	static function same(a:Quat, b:Quat):Bool
		return Math.abs(Math.abs(a.x * b.x + a.y * b.y + a.z * b.z + a.w * b.w) - 1) < 1e-5;

	static function main() {
		ashui.theme.ThemeState.init(ashui.theme.themes.DefaultTheme.bundle(), Dark);
		var offscreen = Offscreen.create();
		for (scale in [1, 2]) {
			var tree = new LayoutTree(), dispose:Void->Void = null, kit:SceneKit = null;
			var reference = new Ref<SceneKit>();
			var camera = new OrbitCamera(0.55, 0.4, 6, Vec3.ZERO, 0.7);
			var selection:Selection3D = null, rotation:Signal<Quat> = null;
			var draws = 0, changes = 0, show = true;
			var box = Geometry.box(1, 1, 1, new Material({baseColor: 0x999999, unlit: true}));
			var root:Div = Owner.root(tree, stop -> {
				dispose = stop;
				selection = new Selection3D(); rotation = Signal.make(Quat.IDENTITY);
				var turn = (delta:Quat) -> {changes++; rotation.set(delta.mul(rotation.get()).normalize());};
				return <div width={800} height={560}>
					<scene-kit ref={reference} camera={camera} width={800} height={560} selection={selection} worldGizmo={true}
						draw={ctx -> {
							draws++;
							if (show) {
								var at = Mat4.rotation(rotation.get()); ctx.drawMesh(box, at);
								selection.region("box", box.min, box.max, at, turn);
							}
						}} />
				</div>;
			});
			kit = reference.get();
			offscreen.scale = scale;
			var texture = offscreen.createTexture(800 * scale, 560 * scale), view = texture.createView(new GpuTextureViewDescriptor());
			function render() offscreen.render(root, view, 800, 560);
			function click(x:Float, y:Float) { Pointer.move(tree, x, y); Pointer.press(tree); Pointer.release(tree); render(); }
			render(); click(400, 280);
			check('clicking mesh bounds selects an object at ${scale}x', selection.has("box"));
			var data = offscreen.readRgba8(texture, 800 * scale, 560 * scale);
			var counts = [0, 0, 0];
			for (y in 170 * scale...390 * scale) for (x in 290 * scale...510 * scale) {
				var i = (y * 800 * scale + x) * 4, r = data.get(i), g = data.get(i + 1), b = data.get(i + 2);
				if (r > 170 && r - g > 20 && r - b > 20) counts[0]++;
				if (g > 140 && g - r > 20 && g - b > 20) counts[1]++;
				if (b > 170 && b - r > 20 && b - g > 20) counts[2]++;
			}
			check('red green blue rotation rings render above the mesh at ${scale}x ($counts)', counts[0] > 20 && counts[1] > 20 && counts[2] > 20);
			var dir = Sys.getEnv("ASHUI_SNAPSHOT_DIR");
			if (dir == null) dir = "../../.ashui/snapshots";
			sys.FileSystem.createDirectory(dir);
			sys.io.File.saveBytes('$dir/scene-gizmo-test-${scale}x.png', ashui.core.render.Png.encode(800 * scale, 560 * scale, data));
			function handle(axis:Int):{x:Float, y:Float} {
				for (iy in 0...140) for (ix in 0...140) {
					var x = 190 + ix * 3, y = 70 + iy * 3;
					if (kit.gizmos.hit(x, y) == axis) return {x: x, y: y};
				}
				throw 'No handle $axis';
			}
			var beforeA = camera.azimuth.get(), beforeE = camera.elevation.get();
			for (axis in 0...4) {
				var p = handle(axis), before = rotation.get();
				Pointer.move(tree, p.x, p.y); Pointer.press(tree); Pointer.move(tree, p.x + 15, p.y + 13); render();
				check('handle $axis rotates the selected object at ${scale}x', !same(before, rotation.get()));
				check('handle $axis leaves orbit camera unchanged at ${scale}x', camera.azimuth.get() == beforeA && camera.elevation.get() == beforeE);
				Pointer.release(tree); render();
				check('handle $axis releases its captured pointer hook at ${scale}x', Pointer.hooks.length == 0);
			}
			var p = handle(2), initial = rotation.get();
			Pointer.move(tree, p.x, p.y); Pointer.press(tree); Pointer.move(tree, p.x + 18, p.y + 10); render();
			Keyboard.input(tree, Input(Code(Escape), Named(Escape), null, Standard, Pressed, false, null)); render();
			check('Escape restores rotation and removes capture at ${scale}x', same(initial, rotation.get()) && Pointer.hooks.length == 0);
			Pointer.release(tree); render();
			var settled = draws; render(); tree.flush();
			check('settled scene adds no idle draw or pointer hook at ${scale}x', draws == settled && Pointer.hooks.length == 0);
			var emptyChanges = changes;
			Pointer.move(tree, 30, 480); Pointer.move(tree, 35, 480); render();
			check('empty hover does not redraw or rotate at ${scale}x', draws == settled && changes == emptyChanges);
			// Edge-on planes must stay finite when ray/plane intersection degenerates.
			camera.azimuth.set(0); camera.elevation.set(0); render();
			for (axis in [0, 1]) {
				var point = handle(axis), before = rotation.get();
				Pointer.move(tree, point.x, point.y); Pointer.press(tree);
				Pointer.move(tree, point.x + 12, point.y + 12); render(); Pointer.release(tree); render();
				var q = rotation.get();
				check('edge-on axis $axis rotates without NaNs at ${scale}x', !same(before, q) && Math.isFinite(q.x + q.y + q.z + q.w));
			}
			camera.reset(); rotation.set(initial); render();
			// Native local coordinates preserve an identical gesture through a CSS scale.
			var point = handle(2);
			Pointer.move(tree, point.x, point.y); Pointer.press(tree);
			Pointer.move(tree, point.x + 15, point.y + 12); render(); var normalTurn = rotation.get();
			var distance = camera.distance.get(); Pointer.wheel(tree, 0, 50); render();
			check('wheel cannot move the camera during object rotation at ${scale}x', camera.distance.get() == distance);
			Keyboard.input(tree, Input(Code(Escape), Named(Escape), null, Standard, Pressed, false, null)); Pointer.release(tree); render();
			kit.node.set(ashui.layout.Prop.Transform, ashui.types.Transform.scaling(0.75)); render();
			Pointer.move(tree, 400 + (point.x - 400) * 0.75, 280 + (point.y - 280) * 0.75); Pointer.press(tree);
			Pointer.move(tree, 400 + (point.x + 15 - 400) * 0.75, 280 + (point.y + 12 - 280) * 0.75); render();
			check('CSS scale preserves captured rotation in canvas coordinates at ${scale}x', same(normalTurn, rotation.get()));
			Keyboard.input(tree, Input(Code(Escape), Named(Escape), null, Standard, Pressed, false, null)); Pointer.release(tree);
			kit.node.set(ashui.layout.Prop.Transform, ashui.types.Transform.identity()); render();
			// Each world arm is tested through the same pointer events as the native window.
			for (arm in 0...6) {
				var axis = Std.int(arm / 2), positive = (arm & 1) == 1, wanted = 4 + arm, found = false;
				for (y in 16...112) {
					for (x in 688...784) if (!found && kit.gizmos.hit(x, y) == wanted) { click(x, y); found = true; }
					if (found) break;
				}
				var azimuth = axis == 0 ? (positive ? Math.PI / 2 : -Math.PI / 2) : axis == 2 && !positive ? Math.PI : 0;
				var elevation = axis == 1 ? (positive ? camera.maxElevation : -camera.maxElevation) : 0;
				check('world arm $arm sets its camera view at ${scale}x', found && Math.abs(camera.azimuth.get() - azimuth) < 1e-5
					&& Math.abs(camera.elevation.get() - elevation) < 1e-5);
				check('world arm $arm keeps orbit target, distance and object rotation at ${scale}x', selection.has("box") && same(initial, rotation.get())
					&& camera.target.get().distance(Vec3.ZERO) < 1e-6 && camera.distance.get() == distance);
				camera.reset(); render();
			}
			// Inverse transformed bounds choose the nearest object, even with nonuniform scale.
			selection.region("far", box.min, box.max, Mat4.translation(new Vec3(0, 0, -3)));
			selection.region("near", box.min, box.max, Mat4.compose(new Vec3(0, 0, 2), Quat.euler(0.2, 0.4, 0), new Vec3(0.4, 2, 1)));
			selection.region("singular", box.min, box.max, Mat4.scaling(Vec3.ZERO));
			check('picking chooses nearest scaled bounds and ignores singular transforms at ${scale}x', selection.pick(new Vec3(0, 0, 10), new Vec3(0, 0, -1)) == "near");
			click(10, 530);
			check('empty click clears selection at ${scale}x', selection.id.get() == null && kit.gizmos.hit(400, 350) == -1);
			selection.select("box"); render(); point = handle(1);
			Pointer.move(tree, point.x, point.y); Pointer.press(tree); Pointer.move(tree, point.x + 10, point.y + 10); render();
			selection.clear(); render();
			check('changing selection cancels rotation and releases capture at ${scale}x', same(initial, rotation.get()) && Pointer.hooks.length == 0);
			Pointer.release(tree);
			selection.select("box"); show = false; render();
			check('removed object bounds and rings disappear at ${scale}x', selection.get("box") == null);
			var azimuth = camera.azimuth.get();
			Pointer.move(tree, 60, 460); Pointer.press(tree); Pointer.move(tree, 90, 470); render();
			check('empty-space drag still orbits the camera at ${scale}x', camera.azimuth.get() != azimuth);
			Pointer.release(tree);
			selection.region("cleanup", box.min, box.max);
			dispose(); tree.dispose(); view.destroy(); texture.destroy();
			check('owner cleanup releases all gizmo pointer hooks at ${scale}x', Pointer.hooks.length == 0);
			check('owner cleanup releases registered object bounds at ${scale}x', selection.get("cleanup") == null);
		}
	}
}
