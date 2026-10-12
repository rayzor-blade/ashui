import ashui.canvaskit.Geometry;
import ashui.canvaskit.GroundGrid;
import ashui.canvaskit.GizmoMode;
import ashui.canvaskit.OrbitCamera;
import ashui.canvaskit.SceneKit;
import ashui.canvaskit.Selection3D;
import ashui.components.Badge;
import ashui.components.Button;
import ashui.components.Toggle.ToggleGroup;
import ashui.components.Toggle.ToggleGroupItem;
import ashui.draw3d.Material;
import ashui.math.Mat4;
import ashui.math.Quat;
import ashui.math.Vec3;
import ashui.reactive.Reactive;
import ashui.types.Style;

/** Object rotation, local scaling and world orientation; offscreen too (c16e24c, 6a3a68b). **/
class SceneGizmos {
	static function main() {
		var build = () -> {
			var selection = new Selection3D();
			selection.select("box");
			var rotation = signal(Quat.euler(0.15, 0.3, 0));
			var otherRotation = signal(Quat.IDENTITY);
			var scale = signal(Vec3.ONE), otherScale = signal(Vec3.ONE);
			var tool = signal(["orbit"]);
			var mode = computed(() -> tool.get()[0] == "scale" ? GizmoMode.Scale : GizmoMode.Orbit);
			var camera = new OrbitCamera(0.55, 0.4, 7, new Vec3(0, 0.55, 0), 0.7);
			var box = Geometry.box(1.2, 1.2, 1.2, new Material({baseColor: 0x80a7eb, roughness: 0.3, metallic: 0.25}));
			var torus = Geometry.torus(0.6, 0.18, 48, 24, new Material({baseColor: 0xf0ba75, roughness: 0.25, metallic: 0.5}));
			var turn = (delta:Quat) -> rotation.set(delta.mul(rotation.get()).normalize());
			var turnOther = (delta:Quat) -> otherRotation.set(delta.mul(otherRotation.get()).normalize());
			var resize = (delta:Vec3) -> scale.set(scale.get().mul(delta));
			var resizeOther = (delta:Vec3) -> otherScale.set(otherScale.get().mul(delta));
			return <div class="w-full h-full">
				<scene-kit camera={camera} selection={selection} gizmoMode={mode} worldGizmo={true} antialias={true}
					grid={GroundGrid.studio()} widthPercent={1} heightPercent={1}
					draw={ctx -> {
						var at = Mat4.compose(new Vec3(-1.05, 0.8, 0), rotation.get(), scale.get());
						selection.draw("box", ctx, () -> ctx.drawMesh(box, at));
						selection.region("box", box.min, box.max, at, turn, null, resize);
						var other = Mat4.compose(new Vec3(1.3, 0.8, 0), otherRotation.get(), otherScale.get());
						selection.draw("torus", ctx, () -> ctx.drawMesh(torus, other));
						selection.region("torus", torus.min, torus.max, other, turnOther, null, resizeOther);
					}} />
				<div position={Absolute} left={24} top={24} class="flex flex-col gap-2" pointerEvents={ashui.types.Style.PointerEvents.None}>
					<text class="text-2xl font-semibold">Scene controls</text>
					<text class="text-sm text-text-secondary">${mode.get() == GizmoMode.Scale ? "Drag an axis to scale · Center grip scales uniformly · Escape to cancel" : "Select an object · Drag a ring to rotate · Escape to cancel"}</text>
				</div>
				<div id="gizmo-toolbar" position={Absolute} left={24} bottom={24} class="flex items-center gap-4 px-4 py-3 rounded-xl bg-surface/80 backdrop-blur-md border border-border">
					<badge id="gizmo-selection" alignSelf={Center}>${selection.id.get() == "box" ? "Box selected" : selection.id.get() == "torus" ? "Torus selected" : "No selection"}</badge>
					<toggle-group id="gizmo-mode" value={tool} variant={Outline} alignSelf={Center}>
						<toggle-group-item id="gizmo-orbit" value="orbit">Orbit</toggle-group-item>
						<toggle-group-item id="gizmo-scale" value="scale">Scale</toggle-group-item>
					</toggle-group>
					<button id="gizmo-reset" variant={Outline} onClick={_ -> { rotation.set(Quat.euler(0.15, 0.3, 0)); otherRotation.set(Quat.IDENTITY); scale.set(Vec3.ONE); otherScale.set(Vec3.ONE); camera.reset(); }}>Reset view</button>
				</div>
			</div>;
		};
		#if ashui_window
		ashui.app.WindowedApp.run({title: "Scene gizmos", width: 1000, height: 700}, build);
		#else
		ashui.theme.ThemeState.init(ashui.theme.themes.DefaultTheme.bundle(), Dark);
		var tree = new ashui.layout.LayoutTree(), cleanup:Void->Void = null;
		var root = ashui.reactive.Owner.root(tree, stop -> { cleanup = stop; return build(); });
		function settle() for (_ in 0...15) {
			ashui.core.render.Offscreen.advance(1 / 60);
			ashui.css.Css.setViewport(1000, 700); ashui.css.Css.update();
			tree.flush(); tree.computeLayout(root.node, 1000, 700);
		}
		function node(id:String) return new ashui.layout.Node(ashui.css.Css.query(tree, root.node.id, '#$id')[0]);
		settle();
		var badge = tree.getBounds(node("gizmo-selection")), toggle = tree.getBounds(node("gizmo-mode")), reset = tree.getBounds(node("gizmo-reset"));
		var center = badge.y + badge.height / 2;
		if (Math.abs(center - (toggle.y + toggle.height / 2)) > 0.5 || Math.abs(center - (reset.y + reset.height / 2)) > 0.5)
			throw "Gizmo toolbar controls must share a vertical center";
		ashui.core.render.Snapshot.capture("scene-gizmos", tree, root.node, 1000, 700, 0x111822, 1, 2);
		// Capture the same scene after using the real mode control (6a3a68b).
		var scale = node("gizmo-scale"), bounds = tree.getBounds(scale);
		ashui.input.Pointer.move(tree, bounds.x + bounds.width / 2, bounds.y + bounds.height / 2);
		ashui.input.Pointer.press(tree); ashui.input.Pointer.release(tree);
		settle();
		if (ashui.css.Identity.of(tree, scale.id).attribute("data-state") != "on") throw "Scale mode did not activate";
		ashui.input.Pointer.leave(tree); settle();
		ashui.core.render.Snapshot.capture("scene-gizmos-scale", tree, root.node, 1000, 700, 0x111822, 1, 2);
		cleanup();
		#end
	}
}
