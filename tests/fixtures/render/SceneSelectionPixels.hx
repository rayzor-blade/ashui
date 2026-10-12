import ashui.canvaskit.Geometry;
import ashui.canvaskit.OrbitCamera;
import ashui.canvaskit.SceneKit;
import ashui.canvaskit.Selection3D;
import ashui.canvaskit.SelectionEdges;
import ashui.core.render.Offscreen;
import ashui.draw3d.Material;
import ashui.input.Pointer;
import ashui.layout.LayoutTree;
import ashui.math.Mat4;
import ashui.math.Vec3;
import ashui.reactive.Owner;
import ashui.reactive.Signal;
import ashui.types.Brush;
import ashui.ui.Div;
import gpu.GpuTextureViewDescriptor;

/** Actual selection surfaces, silhouettes, occlusion and cache lifetime. git-bug 8ceba8d. **/
class SceneSelectionPixels {
	static function check(name:String, ok:Bool):Void {
		if (!ok) throw name;
		Sys.println('ok   $name');
	}

	static function main() {
		ashui.theme.ThemeState.init(ashui.theme.themes.DefaultTheme.bundle(), Dark);
		var offscreen = Offscreen.create();
		var box = Geometry.box(1, 1, 1, new Material({baseColor: 0x999999, unlit: true}));
		var torus = Geometry.torus(0.65, 0.16, 48, 24, box.material);
		var foreground = Geometry.box(0.6, 0.6, 0.6, new Material({baseColor: 0xe55278, unlit: true}));
		var other = Geometry.box(0.5, 0.5, 0.5, new Material({baseColor: 0xdb8250, unlit: true}));
		check('cube UV and normal seams weld to twelve real edges, without triangle diagonals', SelectionEdges.geometry(box).length == 12 * 64);
		var smooth = SelectionEdges.geometry(torus), seams = 0;
		for (i in 0...Std.int(smooth.length / 64)) if (smooth.getFloat(i * 64 + 44) > 0.5) seams++;
		check('smooth torus has no false boundary or crease at its UV seams', seams == 0);
		var fractional = Geometry.box(0.00125, 0.0025, 0.00375);
		var edgeBytes = SelectionEdges.geometry(fractional);
		check('edge geometry preserves fractional dimensions', edgeBytes.length == 12 * 64 && Math.abs(Math.abs(edgeBytes.getFloat(0)) - 0.000625) < 1e-9);
		for (scale in [1, 2]) {
			var tree = new LayoutTree(), stop:Void->Void = null;
			var selection:Selection3D = null, mode:Signal<Int> = null, occluded:Signal<Bool> = null;
			var camera = new OrbitCamera(0.55, 0.4, 4, Vec3.ZERO, 0.75), draws = 0;
			var root:Div = Owner.root(tree, dispose -> {
				stop = dispose; selection = new Selection3D(); mode = Signal.make(0); occluded = Signal.make(false);
				return <div width={420} height={320} bg={Brush.solid(0x121923)}>
					<scene-kit camera={camera} selection={selection} width={420} height={320} draw={ctx -> {
						draws++;
						var mesh = mode.get() == 0 ? box : torus;
						selection.draw("main", ctx, () -> ctx.drawMesh(mesh));
						selection.region("main", mesh.min, mesh.max);
						var at = Mat4.translation(new Vec3(1.5, 0, 0));
						selection.draw("other", ctx, () -> ctx.drawMesh(other, at));
						selection.region("other", other.min, other.max, at);
						if (occluded.get()) ctx.drawMesh(foreground, Mat4.translation(camera.eye().normalize().scale(0.95)));
					}} />
				</div>;
			});
			offscreen.scale = scale;
			var w = 420 * scale, h = 320 * scale;
			var texture = offscreen.createTexture(w, h), view = texture.createView(new GpuTextureViewDescriptor());
			function render():haxe.io.Bytes { offscreen.render(root, view, 420, 320); return offscreen.readRgba8(texture, w, h); }
			var before = render(); selection.select("main"); var selected = render();
			var center = (160 * scale * w + 210 * scale) * 4;
			var delta = before.get(center) - selected.get(center);
			check('selection has a slight surface mask at ${scale}x ($delta)', delta > 8 && delta < 30);
			var edges = 0, untouched = 0, altered = 0;
			for (i in 0...w * h) {
				var at = i * 4, r = selected.get(at), b = selected.get(at + 2);
				if (b > 185 && b - r > 15) edges++;
				if (before.get(at) == 0xdb && before.get(at + 1) == 0x82 && before.get(at + 2) == 0x50) {
					untouched++;
					if (r != 0xdb || selected.get(at + 1) != 0x82 || b != 0x50) altered++;
				}
			}
			check('selected cube has visible edge highlights without rotation rings at ${scale}x ($edges)', edges > 60 * scale);
			check('unselected object keeps its original material at ${scale}x', untouched > 100 * scale && altered == 0);
			selection.clear(); var cleared = render();
			check('deselection restores original pixels at ${scale}x', haxe.crypto.Sha256.make(before).toHex() == haxe.crypto.Sha256.make(cleared).toHex());
			occluded.set(true); before = render(); selection.select("main"); selected = render();
			var covered = 0, leaked = 0;
			for (i in 0...w * h) {
				var at = i * 4;
				if (before.get(at) == 0xe5 && before.get(at + 1) == 0x52 && before.get(at + 2) == 0x78) {
					covered++;
					if (selected.get(at) != 0xe5 || selected.get(at + 1) != 0x52 || selected.get(at + 2) != 0x78) leaked++;
				}
			}
			check('foreground mesh hides selected edges and mask at ${scale}x', covered > 100 * scale && leaked == 0);
			occluded.set(false); selection.clear(); mode.set(1); camera.elevation.set(1.0); before = render();
			selection.select("main"); selected = render();
			check('torus hole stays clear instead of receiving a bounds mask at ${scale}x', before.get(center) == selected.get(center) && before.get(center + 2) == selected.get(center + 2));
			var dir = Sys.getEnv("ASHUI_SNAPSHOT_DIR"); if (dir == null) dir = "../../.ashui/snapshots";
			sys.FileSystem.createDirectory(dir);
			sys.io.File.saveBytes('$dir/scene-selection-${scale}x.png', ashui.core.render.Png.encode(w, h, selected));
			edges = 0;
			// Curved silhouettes are depth-tested: their inside half is hidden by the surface.
			// Check the visible fringe over pixels that were pure background, rather than brightness on a face.
			for (i in 0...w * h) {
				var at = i * 4;
				if (before.get(at) == 0x12 && before.get(at + 1) == 0x19 && before.get(at + 2) == 0x23
					&& selected.get(at + 2) > 60 && selected.get(at + 2) - selected.get(at) > 15) edges++;
			}
			check('curved mesh has highlighted silhouettes at ${scale}x ($edges)', edges > 60 * scale);
			var settled = draws; render();
			check('settled selection adds no idle draws or pointer hooks at ${scale}x', draws == settled && Pointer.hooks.length == 0);
			stop(); tree.dispose(); view.destroy(); texture.destroy();
			check('selection owner cleanup drops registered meshes at ${scale}x', selection.get("main") == null);
		}
	}
}
