import ashui.core.render.Offscreen;
import ashui.layout.LayoutTree;
import ashui.layout.Prop;
import ashui.types.Brush;
import ashui.types.Color;
import ashui.types.CornerRadius;
import ashui.types.Shadow;
import ashui.types.Style;
import ashui.ui.Div;
import gpu.GpuExtent3D;
import gpu.GpuInstance;
import gpu.GpuTextureDescriptor;
import gpu.GpuTextureViewDescriptor;
import gpu.Power;
import gpu.TextureFormat;
import gpu.TextureUsage;

/**
	Renders a scene with `Offscreen` and checks pixels read back from it,
	twice: into a texture this program makes on its own device, as a host
	would, and through `renderToRgba8` on a BGRA renderer. On a white
	64×64 root, absolutely placed:
	- a red 20×20 square at (8,8) casting a black shadow 6px down, blur 2;
	- a blue circle of radius 12 at (32,8) with a 2px green border;
	- a 24×16 bar at (8,40), a gradient from red on the left to blue;
	- a 16×16 box at (40,40) that clips a 32×32 green child to itself.

	Then text, on white: black "MM" at 24px, which must ink pixels, and "MM"
	at 10px under a 4x zoom, whose stem edges must stay about a pixel wide,
	as a glyph rasterized at its on-screen size has and a magnified one,
	about four pixels, does not.
**/
class Pixels {
	static inline var SIZE = 64;
	static inline var ROW = SIZE * 4;

	static function main() {
		var tree = new LayoutTree();
		function at(x:Int, y:Int, w:Int, h:Int, ?bg:Brush, ?children:Array<ashui.layout.Element>) {
			return new Div({
				position: Position.Absolute, left: x, top: y, width: w, height: h, flexShrink: 0, bg: bg
			}, children, tree);
		}
		var square = at(8, 8, 20, 20, Brush.solid(0xff0000));
		square.node.set(Prop.Shadow, new Shadow(0, 6, 2, 0x000000));
		var circle = new Div({
			position: Position.Absolute, left: 32, top: 8, width: 24, height: 24, cornerRadius: CornerRadius.all(12),
			bg: Brush.solid(0x0000ff), borderColor: new Color(0x00ff00), borderWidth: 2
		}, tree);
		var bar = at(8, 40, 24, 16, Brush.linearGradient(0, 0, 24, 0, 0xff0000, 1, 0x0000ff, 1));
		var clipper = new Div({
			position: Position.Absolute, left: 40, top: 40, width: 16, height: 16, overflow: Overflow.Clip
		}, [at(0, 0, 32, 32, Brush.solid(0x00ff00))], tree);
		var root = new Div({width: SIZE, height: SIZE, bg: Brush.solid(0xffffff)}, [square, circle, bar, clipper], tree);
		// As a host would: its own device and texture, the UI drawn into them.
		var device = new GpuInstance().requestAdapter(Power.HighPerformance).await().requestDevice().await();
		var size = new GpuExtent3D(SIZE);
		size.height(SIZE);
		var target = device.texture(new GpuTextureDescriptor(size, TextureFormat.Rgba8unorm, TextureUsage.RENDER_ATTACHMENT | TextureUsage.COPY_SRC));
		var offscreen = new Offscreen(device, TextureFormat.Rgba8unorm);
		offscreen.render(root, target.createView(new GpuTextureViewDescriptor()), SIZE, SIZE);
		var shared = offscreen.readRgba8(target, SIZE, SIZE);
		target.destroy();
		// Read back from a BGRA target, which must come out RGBA.
		var bgra = new Offscreen(device, TextureFormat.Bgra8unorm).renderToRgba8(root, SIZE, SIZE);

		var failures = 0;
		var pixels = shared;
		var label = "";
		function probe(name:String, x:Int, y:Int, ok:(r:Int, g:Int, b:Int) -> Bool) {
			var at = y * ROW + x * 4;
			var rgba = [for (c in 0...4) pixels.get(at + c)];
			var passed = ok(rgba[0], rgba[1], rgba[2]) && rgba[3] == 255;
			if (!passed)
				failures++;
			Sys.println('${passed ? "ok  " : "FAIL"} $label$name ($x,$y): $rgba');
		}
		function near(want:Int)
			return (r, g, b) -> Math.abs(r - (want >> 16 & 0xff)) <= 2 && Math.abs(g - (want >> 8 & 0xff)) <= 2 && Math.abs(b - (want & 0xff)) <= 2;
		probe("root fill", 2, 2, near(0xffffff));
		probe("square fill", 18, 18, near(0xff0000));
		probe("shadow below the square", 18, 31, (r, g, b) -> r < 40 && g < 40 && b < 40);
		probe("no shadow above the square", 18, 4, near(0xffffff));
		probe("circle fill", 44, 20, near(0x0000ff));
		probe("outside the circle's corner", 33, 9, near(0xffffff));
		probe("circle border", 44, 9, near(0x00ff00));
		probe("gradient start", 9, 48, (r, g, b) -> r > 220 && b < 35 && g < 5);
		probe("gradient middle", 20, 48, (r, g, b) -> r > 100 && r < 155 && b > 100 && b < 155);
		probe("gradient end", 31, 48, (r, g, b) -> b > 220 && r < 35 && g < 5);
		probe("clipped child inside the clip", 48, 48, near(0x00ff00));
		probe("clipped child outside the clip", 60, 48, near(0xffffff));
		pixels = bgra;
		label = "bgra: ";
		probe("root fill", 2, 2, near(0xffffff));
		probe("square fill", 18, 18, near(0xff0000));
		probe("shadow below the square", 18, 31, (r, g, b) -> r < 40 && g < 40 && b < 40);
		probe("no shadow above the square", 18, 4, near(0xffffff));
		probe("circle fill", 44, 20, near(0x0000ff));
		probe("outside the circle's corner", 33, 9, near(0xffffff));
		probe("circle border", 44, 9, near(0x00ff00));
		probe("gradient start", 9, 48, (r, g, b) -> r > 220 && b < 35 && g < 5);
		probe("gradient middle", 20, 48, (r, g, b) -> r > 100 && r < 155 && b > 100 && b < 155);
		probe("gradient end", 31, 48, (r, g, b) -> b > 220 && r < 35 && g < 5);
		probe("clipped child inside the clip", 48, 48, near(0x00ff00));
		probe("clipped child outside the clip", 60, 48, near(0xffffff));

		var textTree = new LayoutTree();
		var label24 = new ashui.ui.Text("MM", {fontSize: 24, color: new Color(0x000000), wrap: false}, textTree);
		var plain = new Div({position: Position.Absolute, left: 8, top: 8}, [label24], textTree);
		var label10 = new ashui.ui.Text("MM", {fontSize: 10, color: new Color(0x000000), wrap: false}, textTree);
		var zoomed = new Div({position: Position.Absolute, left: 144, top: 56, width: 32, height: 16}, [label10], textTree);
		zoomed.node.set(Prop.Transform, new ashui.types.Transform(0, 0, 0, 4, 4));
		var textRoot = new Div({width: 4 * SIZE, height: 2 * SIZE, bg: Brush.solid(0xffffff)}, [plain, zoomed], textTree);
		var w = 4 * SIZE;
		var h = 2 * SIZE;
		var text = offscreen.renderToRgba8(textRoot, w, h);
		function ink(x0:Int, y0:Int, x1:Int, y1:Int) {
			var full = 0;
			var partial = 0;
			for (y in y0...y1)
				for (x in x0...x1) {
					var r = text.get((y * w + x) * 4);
					if (r < 40)
						full++;
					else if (r < 215)
						partial++;
				}
			return {full: full, partial: partial};
		}
		var small = ink(0, 0, 64, 48);
		label = "text: ";
		var inked = small.full > 40;
		if (!inked)
			failures++;
		Sys.println('${inked ? "ok  " : "FAIL"} text: 24px glyphs ink ${small.full} pixels');
		// Across each row of the zoomed text, how many pixels the first edge,
		// the left side of the first M's stem, takes from paper to ink.
		var edges = [];
		for (y in 0...h) {
			var x = 80;
			while (x < w && text.get((y * w + x) * 4) >= 215)
				x++;
			var start = x;
			while (x < w && text.get((y * w + x) * 4) >= 40)
				x++;
			if (x < w)
				edges.push(x - start);
		}
		edges.sort((a, b) -> a - b);
		var median = edges.length > 0 ? edges[edges.length >> 1] : -1;
		var sharp = edges.length > 20 && median >= 0 && median <= 2;
		if (!sharp)
			failures++;
		Sys.println('${sharp ? "ok  " : "FAIL"} text: zoomed glyph edges are $median pixels wide over ${edges.length} rows');
		Sys.println(failures == 0 ? "ALL PASSED" : '$failures FAILED');
		Sys.exit(failures == 0 ? 0 : 1);
	}
}
