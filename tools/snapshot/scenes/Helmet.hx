import ashui.canvaskit.Gltf;
import ashui.canvaskit.OrbitCamera;
import ashui.canvaskit.SceneKit;
import ashui.core.render.Snapshot;
import ashui.draw3d.Light;
import ashui.math.Vec3;
import ashui.theme.ThemeState;
import ashui.theme.themes.DefaultTheme;
import ashui.types.Style;

/**
	Khronos' DamagedHelmet (`tools/snapshot/assets/3d`, CC BY-NC, by
	theblueturtle_) read with ashui-canvaskit's `Gltf` and drawn in a
	`<scene-kit>`: its five textures, base colour, metal and roughness,
	normals, glow and occlusion, under a key light. Writes
	`.ashui/snapshots/helmet.png`.
**/
class Helmet {
	static function main() {
		ThemeState.init(DefaultTheme.bundle(), Dark);
		var page = ThemeState.get().color(Background);
		var helmet = Gltf.load("../assets/3d/DamagedHelmet/DamagedHelmet.gltf");
		var camera = new OrbitCamera(0.4, 0.2, 3, null, 0.7);
		camera.frame(helmet.min, helmet.max);
		var rig = [Directional(new Vec3(-0.4, -1, -0.3), 0xffffff, 2.5), Directional(new Vec3(0.6, 0.2, -0.8), 0x8899ff, 0.8)];
		var build = () -> <div padding={20}><scene-kit camera={camera} lights={rig} ambientStrength={0.5} draw={ctx -> helmet.draw(ctx)} width={600} height={600} /></div>;
		Snapshot.scene("helmet", 640, 640, build, page.rgb(), page.a, 2.0, 1.0);
	}
}
