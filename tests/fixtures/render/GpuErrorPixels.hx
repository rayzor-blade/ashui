import ashui.core.render.Offscreen;
import ashui.core.render.Renderer;
import ashui.css.Css;
import ashui.draw.DrawContext;
import ashui.layout.LayoutTree;
import ashui.reactive.Owner;
import ashui.types.Brush;
import gpu.GpuExtent3D;
import ashui.core.render.GpuFlags;
import gpu.GpuTextureDescriptor;
import gpu.GpuTextureViewDescriptor;
import gpu.TextureFormat;

/**
	What the renderer does when the GPU is asked for more than it has: a canvas with more triangles than a texture holds draws
	the first of them and no error comes of it, and a GPU error in a frame throws where the renderer is strict and is counted,
	with the frame going on, where it is not.
**/
class GpuErrorPixels {
	static var checks = 0;

	static function check(what:String, ok:Bool, ?detail:Dynamic):Void {
		if (!ok)
			throw what + (detail == null ? "" : ' ($detail)');
		checks++;
		Sys.println('ok   $what');
	}

	static function main():Void {
		ashui.theme.ThemeState.init(ashui.theme.themes.DefaultTheme.bundle(), Light);
		var sheet = Css.load("#grid { position: absolute; left: 0px; top: 0px; width: 320px; height: 240px; }");
		var tree = new LayoutTree(), dispose = () -> {};
		var grid = (ctx:DrawContext) -> {
			for (row in 0...80)
				for (column in 0...106)
					ctx.fillRect(column * 3, row * 3, 2, 2, Brush.solid(0xdc2626));
		};
		var root = Owner.root(tree, stop -> {
			dispose = stop;
			return <div width={320} height={240} class="bg-background"><canvas id="grid" draw={grid} /></div>;
		});
		var off = Offscreen.create();
		off.clearAlpha = 1.0;
		off.clear = 0xffffff;
		var texture = off.createTexture(320, 240);
		var view = texture.createView(new GpuTextureViewDescriptor());
		function pixel(x:Int, y:Int):Int {
			var bytes = off.readRgba8(texture, 320, 240);
			var at = (y * 320 + x) * 4;
			return bytes.get(at) << 16 | bytes.get(at + 1) << 8 | bytes.get(at + 2);
		}

		var most = Renderer.maxTexture;
		Renderer.maxTexture = 64;
		off.render(root, view, 320, 240);
		check("a canvas of more triangles than its table holds draws without a GPU error", true);
		check("the first of its rects is drawn", pixel(0, 0) == 0xdc2626, StringTools.hex(pixel(0, 0), 6));
		check("a rect past what fits is not", pixel(318, 237) == pixel(2, 2), StringTools.hex(pixel(318, 237), 6));
		Renderer.maxTexture = most;

		function failure():Void {
			var size = new GpuExtent3D(100000);
			size.height(1);
			off.device.texture(new GpuTextureDescriptor(size, TextureFormat.Rgba8unorm, GpuFlags.TEXTURE_BINDING));
		}
		failure();
		var thrown = false;
		try
			off.render(root, view, 320, 240)
		catch (e:Dynamic)
			thrown = Std.string(e).indexOf("gpu error") >= 0;
		check("a GPU error in a frame throws where errors are strict", thrown);

		off.strictErrors = false;
		var before = off.failedFrames;
		failure();
		var survived = true;
		try
			off.render(root, view, 320, 240)
		catch (e:Dynamic)
			survived = false;
		check("it does not throw where they are not", survived);
		check("the frame is counted", off.failedFrames == before + 1, off.failedFrames);
		off.render(root, view, 320, 240);
		check("and the next frame is clean", off.failedFrames == before + 1, off.failedFrames);

		Css.remove(sheet);
		dispose();
		tree.dispose();
		Sys.println('$checks checks: ALL PASSED');
	}
}
