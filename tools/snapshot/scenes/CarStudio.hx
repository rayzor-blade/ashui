import ashui.canvaskit.Geometry;
import ashui.canvaskit.OrbitCamera;
import ashui.canvaskit.SceneKit;
import ashui.core.render.Snapshot;
import ashui.draw3d.Light;
import ashui.draw3d.Material;
import ashui.math.Vec3;
import ashui.theme.ThemeState;
import ashui.theme.themes.DefaultTheme;

/**
	The banner's car alone in a white studio, to judge it. The default view
	is the front-left three-quarters from about head height; `VIEW=side`,
	`front`, `rear` or `top` gives the others, and `DARK=1` the dark studio.
	`PAINT=0xRRGGBB` tints the paint. Writes
	`.ashui/snapshots/car-studio[-view][-dark].png`.
**/
class CarStudio {
	static inline var WIDTH = 1600;
	static inline var HEIGHT = 893;

	static function main() {
		ThemeState.init(DefaultTheme.bundle(), Light);
		var dark = Sys.getEnv("DARK") == "1";
		var paint = Sys.getEnv("PAINT");
		var metal = Sys.getEnv("METAL");
		var car = new BannerCar(paint == null ? 0xb9bec6 : Std.parseInt(paint), metal == null ? 0.0 : Std.parseFloat(metal), Sys.getEnv("TOON") == "1");
		var floor = Geometry.plane(80, 80, 1, new Material({baseColor: dark ? 0x161b23 : 0xf0f1f3, roughness: 0.9}));
		var view = Sys.getEnv("VIEW");
		var camera = switch view {
			case "side": new OrbitCamera(-Math.PI / 2, 0.04, 11, new Vec3(0, 0.7, 0), 0.42);
			case "front": new OrbitCamera(Math.PI, 0.06, 11, new Vec3(0, 0.7, 0), 0.3);
			case "rear": new OrbitCamera(0, 0.1, 11, new Vec3(0, 0.7, 0), 0.3);
			case "top": new OrbitCamera(-Math.PI / 2, 1.5, 12, new Vec3(0, 0.6, 0), 0.5);
			default: new OrbitCamera(Math.PI + 0.82, 0.13, 13.6, new Vec3(0.05, 0.7, 0.15), 0.28);
		};
		var light = [Directional(new Vec3(0.25, -1, 0.2), 0xffffff, 1.4)];
		var background = dark ? 0x161b23 : 0xf4f5f6;
		var build = () -> <div width={WIDTH} height={HEIGHT}>
			<scene-kit camera={camera} lights={light} environment={BannerCar.studio(dark)} environmentIntensity={1.0} antialias={true}
				background={background} shadows={true} shadowStrength={0.45} shadowReach={5.0} draw={ctx -> {ctx.drawMesh(floor); car.draw(ctx);}}
				widthPercent={1} heightPercent={1} />
		</div>;
		var name = "car-studio" + (view == null || view == "" ? "" : "-" + view) + (dark ? "-dark" : "");
		Snapshot.scene(name, WIDTH, HEIGHT, build, background, 1.0, 2.0, 1.0);
	}
}
