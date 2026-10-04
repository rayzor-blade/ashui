import ashui.core.render.Snapshot;
import ashui.draw.DrawContext;
import ashui.draw3d.Camera;
import ashui.draw3d.Light;
import ashui.draw3d.Material;
import ashui.draw3d.MeshData;
import ashui.math.Mat4;
import ashui.math.Quat;
import ashui.math.Vec3;
import ashui.theme.ThemeState;
import ashui.theme.themes.DefaultTheme;
import ashui.types.Brush;
import ashui.types.Style;

/**
	Meshes on a canvas: a row of spheres from polished to rough, plastic
	above and metal below, a turned cube, all lit by a key light and a warm
	point light, with a label drawn over them in 2D. Writes
	`.ashui/snapshots/canvas-mesh.png` (`canvas-mesh-light` with
	`SCHEME=light`).
**/
class CanvasMesh {
	static function sphere(material:Material, rings = 32, segments = 48):MeshData {
		var p = [], uv = [], idx = [];
		for (r in 0...rings + 1) {
			var v = r / rings, phi = v * Math.PI;
			for (s in 0...segments + 1) {
				var u = s / segments, theta = u * Math.PI * 2;
				p.push(-Math.cos(theta) * Math.sin(phi));
				p.push(Math.cos(phi));
				p.push(Math.sin(theta) * Math.sin(phi));
				uv.push(u);
				uv.push(v);
			}
		}
		for (r in 0...rings)
			for (s in 0...segments) {
				var a = r * (segments + 1) + s, b = a + segments + 1;
				for (i in [a, b, a + 1, a + 1, b, b + 1])
					idx.push(i);
			}
		return MeshData.build(p, idx, p.copy(), uv, null, material);
	}

	static function cube(material:Material):MeshData {
		var p = [], n = [], idx = [];
		var faces = [[1, 0, 0], [-1, 0, 0], [0, 1, 0], [0, -1, 0], [0, 0, 1], [0, 0, -1]];
		for (f in faces) {
			var normal = new Vec3(f[0], f[1], f[2]);
			var u = Math.abs(normal.y) > 0.5 ? new Vec3(1, 0, 0) : new Vec3(0, 1, 0);
			var v = normal.cross(u);
			var base = Std.int(p.length / 3);
			for (c in [[-1, -1], [1, -1], [1, 1], [-1, 1]]) {
				var q = normal.add(u.scale(c[0])).add(v.scale(c[1])).scale(0.5);
				p.push(q.x);
				p.push(q.y);
				p.push(q.z);
				n.push(normal.x);
				n.push(normal.y);
				n.push(normal.z);
			}
			// Counter-clockwise seen from outside: u, then v, is that way round from the normal.
			for (i in [0, 2, 1, 0, 3, 2])
				idx.push(base + i);
		}
		return MeshData.build(p, idx, n, null, null, material);
	}

	static function main() {
		var light = Sys.getEnv("SCHEME") == "light";
		ThemeState.init(DefaultTheme.bundle(), light ? Light : Dark);
		var theme = ThemeState.get();
		var page = theme.color(Background), ink = theme.color(TextPrimary).rgb();
		var plastic = [for (i in 0...5) sphere(new Material({baseColor: 0xd94040, roughness: 0.1 + i * 0.2}))];
		var metal = [for (i in 0...5) sphere(new Material({baseColor: 0xe0b060, metallic: 1, roughness: 0.1 + i * 0.2}))];
		var box = cube(new Material({baseColor: 0x4a7fe0, roughness: 0.4}));
		function draw(ctx:DrawContext) {
			ctx.setCamera(new Camera(new Vec3(0, 1.2, 9), new Vec3(0, -0.2, 0), null, 0.6));
			ctx.setLights([
				Directional(new Vec3(-0.5, -1, -0.6), 0xffffff, 2.2),
				Point(new Vec3(3, 2, 3), 0xffaa66, 25, 20)
			]);
			for (i in 0...5) {
				ctx.drawMesh(plastic[i], Mat4.compose(new Vec3(-3.2 + i * 1.6, 0.6, 0), Quat.IDENTITY, new Vec3(0.65, 0.65, 0.65)));
				ctx.drawMesh(metal[i], Mat4.compose(new Vec3(-3.2 + i * 1.6, -1.0, 0), Quat.IDENTITY, new Vec3(0.65, 0.65, 0.65)));
			}
			ctx.drawMesh(box, Mat4.compose(new Vec3(0, -2.4, -1.5), Quat.euler(0.5, 0.7, 0), new Vec3(1.1, 1.1, 1.1)));
			ctx.text("polished to rough", 20, 30, Brush.solid(ink), {size: 16, weight: 600});
		}
		var build = () -> <div padding={20}><canvas width={720} height={420} draw={draw} /></div>;
		Snapshot.scene(light ? "canvas-mesh-light" : "canvas-mesh", 760, 460, build, page.rgb(), page.a, 2.0, 1.0);
	}
}
