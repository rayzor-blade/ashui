import ashui.canvaskit.Geometry;
import ashui.canvaskit.GroundGrid;
import ashui.canvaskit.OrbitCamera;
import ashui.canvaskit.SceneKit;
import ashui.canvaskit.Selection3D;
import ashui.components.Badge;
import ashui.components.Button;
import ashui.draw3d.Material;
import ashui.math.Mat4;
import ashui.math.Quat;
import ashui.math.Vec3;
import ashui.reactive.Reactive;
import ashui.types.Style;

/** Interactive object rotation and world orientation; offscreen too (c16e24c). **/
class SceneGizmos {
	static function main() {
		var build = () -> {
			var selection = new Selection3D();
			selection.select("box");
			var rotation = signal(Quat.euler(0.15, 0.3, 0));
			var otherRotation = signal(Quat.IDENTITY);
			var camera = new OrbitCamera(0.55, 0.4, 7, new Vec3(0, 0.55, 0), 0.7);
			var box = Geometry.box(1.2, 1.2, 1.2, new Material({baseColor: 0x80a7eb, roughness: 0.3, metallic: 0.25}));
			var torus = Geometry.torus(0.6, 0.18, 48, 24, new Material({baseColor: 0xf0ba75, roughness: 0.25, metallic: 0.5}));
			var turn = (delta:Quat) -> rotation.set(delta.mul(rotation.get()).normalize());
			var turnOther = (delta:Quat) -> otherRotation.set(delta.mul(otherRotation.get()).normalize());
			return <div class="w-full h-full">
				<scene-kit camera={camera} selection={selection} worldGizmo={true} antialias={true}
					grid={GroundGrid.studio()} widthPercent={1} heightPercent={1}
					draw={ctx -> {
						var at = Mat4.compose(new Vec3(-1.05, 0.8, 0), rotation.get(), Vec3.ONE);
						selection.draw("box", ctx, () -> ctx.drawMesh(box, at));
						selection.region("box", box.min, box.max, at, turn);
						var other = Mat4.compose(new Vec3(1.3, 0.8, 0), otherRotation.get(), Vec3.ONE);
						selection.draw("torus", ctx, () -> ctx.drawMesh(torus, other));
						selection.region("torus", torus.min, torus.max, other, turnOther);
					}} />
				<div position={Absolute} left={24} top={24} class="flex flex-col gap-2" pointerEvents={ashui.types.Style.PointerEvents.None}>
					<text class="text-2xl font-semibold">Scene controls</text>
					<text class="text-sm text-text-secondary">Select an object · Drag a ring to rotate · Escape to cancel</text>
				</div>
				<div position={Absolute} left={24} bottom={24} class="flex items-center gap-3 px-4 py-3 rounded-xl bg-surface/80 backdrop-blur-md border border-border">
					<badge>${selection.id.get() == "box" ? "Box selected" : selection.id.get() == "torus" ? "Torus selected" : "No selection"}</badge>
					<button variant={Outline} onClick={_ -> { rotation.set(Quat.euler(0.15, 0.3, 0)); otherRotation.set(Quat.IDENTITY); camera.reset(); }}>Reset view</button>
				</div>
			</div>;
		};
		#if ashui_window
		ashui.app.WindowedApp.run({title: "Scene gizmos", width: 1000, height: 700}, build);
		#else
		ashui.theme.ThemeState.init(ashui.theme.themes.DefaultTheme.bundle(), Dark);
		ashui.core.render.Snapshot.scene("scene-gizmos", 1000, 700, build, 0x111822, 1, 2);
		#end
	}
}
