import ashui.canvaskit.Geometry;
import ashui.canvaskit.OrbitCamera;
import ashui.canvaskit.SceneKit;
import ashui.core.render.Snapshot;
import ashui.draw3d.Light;
import ashui.draw3d.Material;
import ashui.math.Mat4;
import ashui.math.Quat;
import ashui.math.Vec3;
import ashui.theme.ThemeState;
import ashui.theme.themes.DefaultTheme;
import ashui.types.Style;

/**
	ashui-canvaskit's shapes in a `<scene-kit>` viewport: a box, a sphere,
	a cylinder and a torus on a floor, seen through an orbit camera, with
	a key light casting shadows and a cool fill. Writes `.ashui/snapshots/scene-kit.png`
	(`scene-kit-light` with `SCHEME=light`).
**/
class SceneKitScene {
	static function main() {
		var light = Sys.getEnv("SCHEME") == "light";
		ThemeState.init(DefaultTheme.bundle(), light ? Light : Dark);
		var page = ThemeState.get().color(Background);
		var camera = new OrbitCamera(0.6, 0.45, 7, new Vec3(0, 0.4, 0), 0.7);
		var rig = [
			Directional(new Vec3(-0.5, -1, -0.4), 0xffffff, 2.4),
			Directional(new Vec3(0.7, -0.3, 0.6), 0x88aaff, 0.6)
		];
		var floor = Geometry.plane(8, 8, 1, new Material({baseColor: light ? 0xd8dbe2 : 0x2a2f3a, roughness: 0.9}));
		var box = Geometry.box(1, 1, 1, new Material({baseColor: 0x4a7fe0, roughness: 0.35}));
		var ball = Geometry.sphere(0.55, 32, 48, new Material({baseColor: 0xe0b060, metallic: 1, roughness: 0.25}));
		var can = Geometry.cylinder(0.45, 1.2, 48, new Material({baseColor: 0x30b070, roughness: 0.5}));
		var ring = Geometry.torus(0.5, 0.18, 48, 24, new Material({baseColor: 0xd94040, roughness: 0.2}));
		function draw(ctx:ashui.draw.DrawContext) {
			ctx.drawMesh(floor);
			ctx.drawMesh(box, Mat4.compose(new Vec3(-1.6, 0.5, 0), Quat.euler(0, 0.5, 0), Vec3.ONE));
			ctx.drawMesh(ball, Mat4.translation(new Vec3(0, 0.55, -0.6)));
			ctx.drawMesh(can, Mat4.translation(new Vec3(1.5, 0.6, -0.2)));
			ctx.drawMesh(ring, Mat4.compose(new Vec3(0.2, 0.7, 1.4), Quat.euler(1.1, 0, 0.2), Vec3.ONE));
		}
		var build = () -> <div padding={20}><scene-kit camera={camera} lights={rig} shadows={true} draw={draw} width={720} height={440} /></div>;
		Snapshot.scene(light ? "scene-kit-light" : "scene-kit", 760, 480, build, page.rgb(), page.a, 2.0, 1.0);
	}
}
