import ashui.core.render.Offscreen;
import ashui.css.Css;
import ashui.layout.LayoutTree;
import ashui.layout.Node;
import ashui.reactive.Owner;
import gpu.GpuTextureViewDescriptor;

/** Nested overflow clips keep each card's rounded child background inside its border. */
class NestedRoundedClipPixels {
	static function main():Void {
		var renderer = Offscreen.create();
		for (theme in [
			ashui.theme.themes.RestrainedTheme.bundle(),
			ashui.theme.themes.HybridTheme.bundle(),
			ashui.theme.themes.ExpressiveTheme.bundle()
		]) {
			ashui.theme.ThemeState.init(theme, Dark);
			for (radius in [24, 48]) {
				var sheet = Css.load('#outer {width:400px;height:300px;overflow:hidden;border:1px solid white;border-radius:${radius}px;background:#102030;}'
					+ '#inner {width:200px;height:150px;margin:50px;overflow:hidden;border:1px solid white;border-radius:24px;background:#222222;}'
					+ '#child {width:100%;height:100%;background:#ff0000;}');
				var tree = new LayoutTree(), dispose = () -> {};
				var root = Owner.root(tree, stop -> {
					dispose = stop;
					return <div id="outer"><div id="inner"><div id="child"/></div></div>;
				});
				for (scale in [1, 2]) {
					renderer.scale = scale;
					var width = 400 * scale, height = 300 * scale;
					var texture = renderer.createTexture(width, height),
						view = texture.createView(new GpuTextureViewDescriptor());
					renderer.render(root, view, 400, 300);
					var pixels = renderer.readRgba8(texture, width, height);
					var inner = tree.getBounds(new Node(Css.query(tree, root.node.id, "#inner")[0]));
					var center = (Std.int((inner.y + inner.height / 2) * scale) * width + Std.int((inner.x + inner.width / 2) * scale)) * 4;
					if (pixels.get(center) < 200 || pixels.get(center + 1) > 80)
						throw "Nested content was not painted";
					for (x in [inner.x + 2, inner.x + inner.width - 3])
						for (y in [inner.y + 2, inner.y + inner.height - 3]) {
							var offset = (Std.int(y * scale) * width + Std.int(x * scale)) * 4;
							if (pixels.get(offset) > 50 || pixels.get(offset + 2) < 35)
								throw 'Nested content escaped its rounded corner at ${scale}x (outer radius $radius)';
						}
					view.destroy();
					texture.destroy();
				}
				dispose();
				tree.dispose();
				Css.remove(sheet);
			}
		}
		Sys.println("ok   nested rounded cards clip child fills in every theme at 1x and 2x");
	}
}
