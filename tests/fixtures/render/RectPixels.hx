import ashui.core.render.Offscreen;
import ashui.css.Css;
import ashui.draw.DrawContext;
import ashui.draw.Tessellate;
import ashui.layout.LayoutTree;
import ashui.reactive.Owner;
import ashui.types.Brush;
import gpu.GpuTextureViewDescriptor;

/**
	A rect along the axes is drawn in two triangles and its edges are faded by their distances; the sweep draws it as a trapezoid
	and a fringe. The two are drawn, rects of whole and fractional sizes and places, thin ones, and ones scaled, and their pixels
	compared.
**/
class RectPixels {
	static var checks = 0;

	static function check(what:String, ok:Bool, ?detail:Dynamic):Void {
		if (!ok)
			throw what + (detail == null ? "" : ' ($detail)');
		checks++;
		Sys.println('ok   $what');
	}

	static function main():Void {
		ashui.theme.ThemeState.init(ashui.theme.themes.DefaultTheme.bundle(), Light);
		var sheet = Css.load("#rects { position: absolute; left: 0px; top: 0px; width: 240px; height: 160px; }");
		var tree = new LayoutTree(), dispose = () -> {};
		var draw = (ctx:DrawContext) -> {
			for (i in 0...12) {
				var f = i * 0.37;
				ctx.fillRect(4 + i * 18 + f, 6 + f, 12 + f * 0.5, 20 + f, Brush.solid(0xdc2626));
				ctx.fillRect(4 + i * 18, 34 + f, 14, 1 + f * 0.1, Brush.solid(0x1d4ed8, 0.8));
				ctx.fillRect(4 + i * 18 + f, 44, 0.4 + f * 0.2, 30, Brush.solid(0x16a34a));
			}
			ctx.fillRect(10.5, 90.25, 100, 50, Brush.solid(0x111827, 0.5));
			ctx.fillRect(60, 100, 150.75, 30.5, Brush.solid(0xfacc15));
		};
		var root = Owner.root(tree, stop -> {
			dispose = stop;
			return <div width={240} height={160} class="bg-background"><canvas id="rects" draw={draw} /></div>;
		});
		var off = Offscreen.create();
		off.clearAlpha = 1.0;
		off.clear = 0xffffff;
		for (scale in [1, 2, 1.5]) {
			off.scale = scale;
			var width = Math.round(240 * scale), height = Math.round(160 * scale);
			var texture = off.createTexture(width, height);
			var view = texture.createView(new GpuTextureViewDescriptor());
			var drawn:Array<haxe.io.Bytes> = [];
			for (fast in [true, false]) {
				Tessellate.axisRects = fast;
				// A new record each time, so the canvas is built again.
				var again = (ctx:DrawContext) -> draw(ctx);
				var rootAgain = Owner.root(new LayoutTree(), stop -> <div width={240} height={160} class="bg-background"><canvas id="rects" draw={again} /></div>);
				off.render(rootAgain, view, 240, 160);
				drawn.push(off.readRgba8(texture, width, height));
			}
			Tessellate.axisRects = true;
			var worst = 0, over = 0, total = 0.0;
			for (i in 0...drawn[0].length) {
				var d = Std.int(Math.abs(drawn[0].get(i) - drawn[1].get(i)));
				total += d;
				if (d > worst)
					worst = d;
				if (d > 16)
					over++;
			}
			check('${scale}x: rects drawn in two triangles match those drawn by the sweep (worst ${worst}, mean ${Math.round(total / drawn[0].length * 100) / 100}, ${over} bytes over 16)',
				worst <= 64 && total / drawn[0].length < 0.2, [worst, over]);
			view.destroy();
			texture.destroy();
		}
		Css.remove(sheet);
		dispose();
		tree.dispose();
		Sys.println('$checks checks: ALL PASSED');
	}
}
