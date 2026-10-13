import ashui.canvaskit.Geometry;
import ashui.canvaskit.GizmoMode;
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

/** Gizmo GPU and real pointer arbitration checks (git-bug c16e24c, 6a3a68b). **/
class SceneGizmoPixels {
	static function check(name:String, ok:Bool) {
		if (!ok) throw name;
		Sys.println('ok   $name');
	}
	static function same(a:Quat, b:Quat):Bool
		return Math.abs(Math.abs(a.x * b.x + a.y * b.y + a.z * b.z + a.w * b.w) - 1) < 1e-5;
	static function sameScale(a:Vec3, b:Vec3):Bool return a.distance(b) < 1e-5;

	static function main() {
		ashui.theme.ThemeState.init(ashui.theme.themes.DefaultTheme.bundle(), Dark);
		var offscreen = Offscreen.create();
		for (scale in [1, 2]) {
			var tree = new LayoutTree(), dispose:Void->Void = null, kit:SceneKit = null;
			var reference = new Ref<SceneKit>();
			var camera = new OrbitCamera(0.55, 0.4, 6, Vec3.ZERO, 0.7);
			var selection:Selection3D = null, rotation:Signal<Quat> = null;
			var size:Signal<Vec3> = null, position:Signal<Vec3> = null, mode:Signal<GizmoMode> = null;
			var rotatable = true, scalable = true, movable = true;
			var draws = 0, changes = 0, show = true;
			var box = Geometry.box(1, 1, 1, new Material({baseColor: 0x999999, unlit: true}));
			var root:Div = Owner.root(tree, stop -> {
				dispose = stop;
				selection = new Selection3D(); rotation = Signal.make(Quat.IDENTITY);
				size = Signal.make(Vec3.ONE); position = Signal.make(Vec3.ZERO); mode = Signal.make(GizmoMode.Orbit);
				var turn = (delta:Quat) -> {changes++; rotation.set(delta.mul(rotation.get()).normalize());};
				var resize = (delta:Vec3) -> size.set(size.get().mul(delta));
				var translate = (delta:Vec3) -> position.set(position.get().add(delta));
				return <div width={800} height={560}>
					<scene-kit ref={reference} camera={camera} width={800} height={560} selection={selection} gizmoMode={mode} worldGizmo={true}
						draw={ctx -> {
							draws++;
							if (show) {
								var at = Mat4.compose(position.get(), rotation.get(), size.get()); selection.draw("box", ctx, () -> ctx.drawMesh(box, at));
								selection.region("box", box.min, box.max, at, rotatable ? turn : null, null, scalable ? resize : null, movable ? translate : null);
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
			// Scale tools share the capture/FSM path, using the object's local axes (6a3a68b).
			mode.set(GizmoMode.Scale); render();
			for (axis in 0...4) {
				size.set(Vec3.ONE); render(); var grip = handle(axis);
				var dx = grip.x - 400, dy = grip.y - 280, length = Math.sqrt(dx * dx + dy * dy);
				if (axis == 3) { dx = 0.7071; dy = -0.7071; } else { dx /= length; dy /= length; }
				Pointer.move(tree, grip.x, grip.y); Pointer.press(tree);
				Pointer.move(tree, grip.x + dx * 18, grip.y + dy * 18); render();
				var now = size.get();
				check('scale grip $axis changes only its local axis, or all axes uniformly, at ${scale}x',
					(axis == 0 || axis == 3 ? now.x > 1.05 : Math.abs(now.x - 1) < 1e-6)
					&& (axis == 1 || axis == 3 ? now.y > 1.05 : Math.abs(now.y - 1) < 1e-6)
					&& (axis == 2 || axis == 3 ? now.z > 1.05 : Math.abs(now.z - 1) < 1e-6));
				check('scale grip $axis preserves rotation and camera at ${scale}x', same(rotation.get(), initial)
					&& camera.azimuth.get() == beforeA && camera.elevation.get() == beforeE && camera.distance.get() == distance);
				Pointer.release(tree); render();
				check('scale grip $axis commits and releases capture at ${scale}x', sameScale(now, size.get()) && Pointer.hooks.length == 0);
			}
			size.set(Vec3.ONE); render(); point = handle(3);
			Pointer.move(tree, point.x, point.y); Pointer.press(tree); Pointer.move(tree, point.x + 20, point.y - 20); render();
			Pointer.wheel(tree, 0, 50); render();
			check('wheel cannot move the camera during scaling at ${scale}x', camera.distance.get() == distance);
			Keyboard.input(tree, Input(Code(Escape), Named(Escape), null, Standard, Pressed, false, null)); render();
			check('Escape restores scale and removes capture at ${scale}x', sameScale(size.get(), Vec3.ONE) && Pointer.hooks.length == 0);
			Pointer.release(tree); render(); point = handle(3);
			Pointer.move(tree, point.x, point.y); Pointer.press(tree); Pointer.move(tree, point.x + 20, point.y - 20); render();
			mode.set(GizmoMode.Orbit); render();
			check('switching to orbit cancels a scale drag at ${scale}x', sameScale(size.get(), Vec3.ONE) && Pointer.hooks.length == 0);
			Pointer.release(tree); render(); point = handle(2);
			Pointer.move(tree, point.x, point.y); Pointer.press(tree); Pointer.move(tree, point.x + 15, point.y + 15); render();
			mode.set(GizmoMode.Scale); render();
			check('switching to scale cancels a rotation drag at ${scale}x', same(rotation.get(), initial) && Pointer.hooks.length == 0);
			Pointer.release(tree); render(); point = handle(3);
			Pointer.move(tree, point.x, point.y); Pointer.press(tree); Pointer.move(tree, point.x + 20, point.y - 20); render();
			selection.clear(); render();
			check('selection change cancels a scale drag at ${scale}x', sameScale(size.get(), Vec3.ONE) && Pointer.hooks.length == 0);
			Pointer.release(tree); selection.select("box"); render(); point = handle(3);
			Pointer.move(tree, point.x, point.y); Pointer.press(tree); Pointer.move(tree, point.x - 2000, point.y + 2000); render();
			check('scale drag remains positive when pulled through the pivot at ${scale}x', Math.abs(size.get().x - 0.05) < 1e-6 && sameScale(size.get(), new Vec3(0.05, 0.05, 0.05)));
			Pointer.move(tree, point.x + 2000, point.y - 2000); render();
			check('large scale drag is bounded and finite at ${scale}x', Math.abs(size.get().x - 20) < 1e-5 && Math.isFinite(size.get().x + size.get().y + size.get().z));
			Keyboard.input(tree, Input(Code(Escape), Named(Escape), null, Standard, Pressed, false, null)); Pointer.release(tree); render();
			rotation.set(Quat.IDENTITY); camera.azimuth.set(0); camera.elevation.set(0); render(); point = handle(2);
			Pointer.move(tree, point.x, point.y); Pointer.press(tree); Pointer.move(tree, point.x + 18, point.y + 18); render();
			check('end-on local axis remains reachable and scales without NaNs at ${scale}x', size.get().z > 1.05 && size.get().x == 1 && size.get().y == 1 && Math.isFinite(size.get().z));
			Keyboard.input(tree, Input(Code(Escape), Named(Escape), null, Standard, Pressed, false, null)); Pointer.release(tree);
			rotation.set(initial); camera.reset(); render(); point = handle(3);
			Pointer.move(tree, point.x, point.y); Pointer.press(tree); Pointer.move(tree, point.x + 18, point.y - 18); render(); var normalScale = size.get();
			Keyboard.input(tree, Input(Code(Escape), Named(Escape), null, Standard, Pressed, false, null)); Pointer.release(tree); render();
			kit.node.set(ashui.layout.Prop.Transform, ashui.types.Transform.scaling(0.75)); render();
			Pointer.move(tree, 400 + (point.x - 400) * 0.75, 280 + (point.y - 280) * 0.75); Pointer.press(tree);
			Pointer.move(tree, 400 + (point.x + 18 - 400) * 0.75, 280 + (point.y - 18 - 280) * 0.75); render();
			check('CSS scale preserves captured object scaling in canvas coordinates at ${scale}x', sameScale(normalScale, size.get()));
			Keyboard.input(tree, Input(Code(Escape), Named(Escape), null, Standard, Pressed, false, null)); Pointer.release(tree);
			kit.node.set(ashui.layout.Prop.Transform, ashui.types.Transform.identity()); render();
			// Known world-axis points project the start and end of an exact translation.
			var endings:Array<Bool> = []; kit.gizmos.onTransformEnd = cancel -> endings.push(cancel);
			mode.set(GizmoMode.Move); size.set(Vec3.ONE); render();
			var worldAxes = [new Vec3(1,0,0), Vec3.UP, new Vec3(0,0,1)];
			data = offscreen.readRgba8(texture, 800 * scale, 560 * scale);
			sys.io.File.saveBytes('$dir/scene-move-test-${scale}x.png', ashui.core.render.Png.encode(800 * scale, 560 * scale, data));
			counts = [0,0,0];
			for (y in 140 * scale...420 * scale) for (x in 260 * scale...540 * scale) {
				var i = (y * 800 * scale + x) * 4, r = data.get(i), g = data.get(i+1), b = data.get(i+2);
				if (r > 170 && r-g > 20 && r-b > 20) counts[0]++;
				if (g > 140 && g-r > 20 && g-b > 20) counts[1]++;
				if (b > 170 && b-r > 20 && b-g > 20) counts[2]++;
			}
			check('translation draws all three colored axes at ${scale}x', counts[0]>20 && counts[1]>20 && counts[2]>20);
			for (axis in 0...3) {
				position.set(Vec3.ZERO); render();
				var start = SceneGizmos.project(camera.camera(), worldAxes[axis].scale(.6),800,560);
				var end = SceneGizmos.project(camera.camera(), worldAxes[axis].scale(1),800,560);
				check('world translation axis $axis is reachable at ${scale}x', kit.gizmos.hit(start.x,start.y)==axis);
				Pointer.move(tree,start.x,start.y); Pointer.press(tree); Pointer.move(tree,end.x,end.y); render();
				check('axis $axis translates exactly 0.4 world units at ${scale}x', position.get().distance(worldAxes[axis].scale(.4))<1e-5);
				end = SceneGizmos.project(camera.camera(),worldAxes[axis].scale(1.2),800,560);
				Pointer.move(tree,end.x,end.y); render();
				check('axis $axis accumulates pointer movement once at ${scale}x', position.get().distance(worldAxes[axis].scale(.6))<1e-5);
				check('translation preserves scale, rotation and camera at ${scale}x', sameScale(size.get(),Vec3.ONE) && same(rotation.get(),initial)
					&& camera.azimuth.get()==beforeA && camera.elevation.get()==beforeE && camera.distance.get()==distance);
				Pointer.release(tree); render(); check('translation releases capture at ${scale}x', Pointer.hooks.length==0);
				check('release reports one committed transform at ${scale}x',endings.length==axis+1 && endings[axis]==false);
			}
			position.set(Vec3.ZERO); render();
			Pointer.move(tree,400,280); Pointer.press(tree); Pointer.move(tree,424,264); render();
			var a = camera.azimuth.get(), e = camera.elevation.get(), unit = 2*Math.tan(camera.fovY.get()/2)*camera.distance.get()/560;
			var right = new Vec3(Math.cos(a),0,-Math.sin(a)), up = new Vec3(-Math.sin(a)*Math.sin(e),Math.cos(e),-Math.cos(a)*Math.sin(e));
			var expected = right.scale(24*unit).add(up.scale(16*unit));
			check('center translates by analytic camera-plane displacement at ${scale}x', position.get().distance(expected)<1e-5);
			Pointer.wheel(tree,0,50); render(); check('wheel cannot zoom during translation at ${scale}x', camera.distance.get()==distance);
			Keyboard.input(tree,Input(Code(Escape),Named(Escape),null,Standard,Pressed,false,null)); Pointer.release(tree); render();
			check('Escape cancels translation and capture at ${scale}x', position.get().length()<1e-6 && Pointer.hooks.length==0);
			check('Escape reports one canceled transform at ${scale}x',endings.length==4 && endings[3]==true);
			kit.node.set(ashui.layout.Prop.Transform, ashui.types.Transform.scaling(.75)); render();
			Pointer.move(tree,400,280); Pointer.press(tree); Pointer.move(tree,418,268); render();
			check('CSS scale preserves translation in canvas coordinates at ${scale}x', position.get().distance(expected)<1e-5);
			mode.set(GizmoMode.Orbit); render(); Pointer.release(tree);
			check('changing tools cancels translation at ${scale}x', position.get().length()<1e-6 && Pointer.hooks.length==0);
			check('mode change reports one canceled transform at ${scale}x',endings.length==5 && endings[4]==true);
			kit.node.set(ashui.layout.Prop.Transform,ashui.types.Transform.identity()); mode.set(GizmoMode.Move); render();
			Pointer.move(tree,400,280); Pointer.press(tree); Pointer.move(tree,424,264); render(); selection.clear(); render(); Pointer.release(tree);
			check('changing selection cancels translation at ${scale}x', position.get().length()<1e-6 && Pointer.hooks.length==0);
			selection.select("box"); camera.azimuth.set(0); camera.elevation.set(0); render();
			var endOn = {x:400+36/Math.sqrt(2),y:280+36/Math.sqrt(2)};
			check('end-on translation has a separate reachable arrow at ${scale}x',kit.gizmos.hit(endOn.x,endOn.y)==2);
			Pointer.move(tree,endOn.x,endOn.y); Pointer.press(tree); Pointer.move(tree,endOn.x+20/Math.sqrt(2),endOn.y+20/Math.sqrt(2)); render();
			check('end-on translation is finite and constrained to Z at ${scale}x',position.get().distance(new Vec3(0,0,20*unit))<1e-5);
			Keyboard.input(tree,Input(Code(Escape),Named(Escape),null,Standard,Pressed,false,null)); Pointer.release(tree); camera.reset(); render();
			movable = false; mode.set(GizmoMode.Orbit); render(); mode.set(GizmoMode.Move); render();
			check('Move skips an object without a translation callback at ${scale}x',kit.gizmos.hit(400,280)==-1);
			movable = true;
			rotatable = false; mode.set(GizmoMode.Orbit); render();
			check('orbit tool skips an object without a rotation handler at ${scale}x', kit.gizmos.hit(400, 280) == -1);
			mode.set(GizmoMode.Scale); render();
			check('scale-only objects still have scale handles at ${scale}x', kit.gizmos.hit(400, 280) == 3);
			scalable = false; mode.set(GizmoMode.Orbit); render(); mode.set(GizmoMode.Scale); render();
			check('scale tool skips an object without a scale handler at ${scale}x', kit.gizmos.hit(400, 280) == -1);
			rotatable = true; scalable = true; mode.set(GizmoMode.Orbit); render();
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
