import ashui.canvaskit.Gltf;
import ashui.canvaskit.GltfPose;
import ashui.canvaskit.GroundGrid;
import ashui.canvaskit.OrbitCamera;
import ashui.canvaskit.SceneKit;
import ashui.core.render.Snapshot;
import ashui.draw3d.Light;
import ashui.math.Vec3;
import ashui.theme.ThemeState;
import ashui.theme.themes.DefaultTheme;
import ashui.types.Style;

/**
	A glTF animation played to a moment: Blinc's Buster Drone (LaVADraGoN,
	CC-BY-4.0), read from Blinc's checkout beside this one, posed by its
	clip `at` seconds in, its rotors and legs where the clip has them then.
	Writes `.ashui/snapshots/gltf-posed.png`.
**/
class GltfPosed {
	static final DRONE = "../../../../Blinc/examples/blinc_app_examples/examples/assets/3d/buster_drone/scene.gltf";

	static function main() {
		ThemeState.init(DefaultTheme.bundle(), Dark);
		var page = ThemeState.get().color(Background);
		var started = haxe.Timer.stamp();
		var drone = Gltf.load(DRONE);
		var clip = drone.animations[0];
		trace('read in ${Math.round((haxe.Timer.stamp() - started) * 1000)}ms: ${drone.nodes.length} nodes, ${drone.meshes.length} meshes, '
			+ '"${clip.name}" ${clip.channels.length} channels over ${Math.round(clip.duration * 10) / 10}s');
		var pose = new GltfPose(drone);
		pose.play(clip, 6);
		var camera = new OrbitCamera(0.6, 0.3, 3, null, 0.7);
		camera.frame(drone.min, drone.max);
		var rig = [Directional(new Vec3(-0.4, -1, -0.3), 0xffffff, 3), Directional(new Vec3(0.6, 0.2, -0.8), 0x8899ff, 0.8)];
		var build = () -> <div padding={20}><scene-kit camera={camera} lights={rig} ambientStrength={0.35} shadows={true}
			grid={GroundGrid.studio(drone.min.y)} draw={ctx -> pose.draw(ctx)} width={600} height={480} /></div>;
		Snapshot.scene("gltf-posed", 640, 520, build, page.rgb(), page.a, 2.0, 1.0);
	}
}
