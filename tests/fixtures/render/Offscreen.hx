import ashui.layout.DisplayList;
import ashui.layout.LayoutTree;
import ashui.layout.Prop;
import ashui.render.Renderer;
import ashui.types.Brush;
import ashui.types.Color;
import ashui.types.CornerRadius;
import ashui.types.Shadow;
import ashui.types.Style;
import ashui.ui.Div;
import gpu.BufferUsage;
import gpu.GpuBufferDescriptor;
import gpu.GpuExtent3D;
import gpu.GpuInstance;
import gpu.GpuTextureDescriptor;
import gpu.GpuTextureViewDescriptor;
import gpu.Power;
import gpu.TextureFormat;
import gpu.TextureUsage;

/**
	Renders a scene offscreen and checks pixels read back from it. On a white
	64×64 root, absolutely placed:
	- a red 20×20 square at (8,8) casting a black shadow 6px down, blur 2;
	- a blue circle of radius 12 at (32,8) with a 2px green border;
	- a 24×16 bar at (8,40), a gradient from red on the left to blue;
	- a 16×16 box at (40,40) that clips a 32×32 green child to itself.
**/
class Offscreen {
	static inline var SIZE = 64;
	static inline var ROW = SIZE * 4; // a multiple of 256, as buffer copies need

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
		tree.flush();
		tree.computeLayout(root.node, SIZE, SIZE);
		var list = new DisplayList();
		list.update(tree, root.node);

		var adapter = new GpuInstance().requestAdapter(Power.HighPerformance).await();
		var device = adapter.requestDevice().await();
		var size = new GpuExtent3D(SIZE);
		size.height(SIZE);
		var target = device.texture(new GpuTextureDescriptor(size, TextureFormat.Rgba8unorm,
			TextureUsage.RENDER_ATTACHMENT | TextureUsage.COPY_SRC));
		var view = target.createView(new GpuTextureViewDescriptor());

		var renderer = new Renderer(device, TextureFormat.Rgba8unorm);
		renderer.draw(list, view, SIZE, SIZE);

		var readback = device.createBuffer(new GpuBufferDescriptor(ROW * SIZE, BufferUsage.MAP_READ | BufferUsage.COPY_DST));
		var encoder = device.encoder();
		encoder.copyTextureToBuffer(target, readback, SIZE, SIZE, ROW);
		encoder.submit(device.queue());
		device.mapBuffer(readback, 0, ROW * SIZE).await();
		var pixels = haxe.io.Bytes.alloc(ROW * SIZE);
		readback.copyOut(0, pixels, ROW * SIZE);
		readback.unmap();
		var error = device.takeError();
		if (error != null)
			throw 'gpu error: $error';

		var failures = 0;
		function probe(name:String, x:Int, y:Int, ok:(r:Int, g:Int, b:Int) -> Bool) {
			var at = y * ROW + x * 4;
			var rgba = [for (c in 0...4) pixels.get(at + c)];
			var passed = ok(rgba[0], rgba[1], rgba[2]) && rgba[3] == 255;
			if (!passed)
				failures++;
			Sys.println('${passed ? "ok  " : "FAIL"} $name ($x,$y): $rgba');
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
		Sys.println(failures == 0 ? "ALL PASSED" : '$failures FAILED');
		Sys.exit(failures == 0 ? 0 : 1);
	}
}
