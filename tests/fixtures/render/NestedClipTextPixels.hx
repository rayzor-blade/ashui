import ashui.core.render.Offscreen;
import ashui.css.Css;
import ashui.layout.LayoutTree;
import ashui.layout.Node;
import ashui.reactive.Owner;
import gpu.GpuTextureViewDescriptor;

/** Text in a rounded clip that an outer clip cuts is drawn (git-bug 9dadd58). **/
class NestedClipTextPixels {
	static function main():Void {
		ashui.theme.ThemeState.init(ashui.theme.themes.DefaultTheme.bundle(), Light);
		var sheet = Css.load('
			#outer { overflow: hidden; border-radius: 24px; width: 260px; height: 110px; background: #e2e8f0; }
			#inner { overflow: hidden; border-radius: 16px; padding: 12px; width: 400px; background: white; margin: 10px; }
			#alone { overflow: hidden; border-radius: 16px; padding: 12px; width: 280px; }
			#cut, #alone-label { color: #ff0000; font-size: 20px; font-weight: 700; }
		');
		var tree = new LayoutTree(), dispose = () -> {};
		var root = Owner.root(tree, stop -> {
			dispose = stop;
			return <div class="bg-background p-6 flex-col gap-4" width={320} height={300}>
				<div id="outer" class="flex-col"><div id="inner" class="flex-col"><text id="cut">A card the outer clip cuts</text></div></div>
				<div id="alone" class="flex-col"><text id="alone-label">Alone in a rounded clip</text></div>
			</div>;
		});
		var renderer = Offscreen.create();
		for (scale in [1, 2]) {
			renderer.scale = scale;
			var width = 320 * scale, height = 300 * scale;
			var texture = renderer.createTexture(width, height), view = texture.createView(new GpuTextureViewDescriptor());
			renderer.render(root, view, 320, 300);
			var pixels = renderer.readRgba8(texture, width, height);
			for (id => name in ["cut" => "in a rounded clip an outer clip cuts", "alone-label" => "in a rounded clip nothing else cuts"]) {
				var found = Css.query(tree, root.node.id, "#" + id);
				if (found.length != 1) throw 'Expected one #$id, got ${found.length}';
				var b = tree.getBounds(new Node(found[0])), ink = 0;
				for (y in Std.int(b.y * scale)...Std.int((b.y + b.height) * scale))
					for (x in Std.int(b.x * scale)...Std.int(Math.min(b.x + b.width, 270) * scale)) {
						var p = (y * width + x) * 4;
						if (pixels.get(p) > 200 && pixels.get(p + 1) < 80 && pixels.get(p + 2) < 80) ink++;
					}
				if (ink < 20 * scale * scale) throw 'No text $name at ${scale}x: $ink ink pixels';
				Sys.println('ok   text $name is drawn at ${scale}x ($ink ink pixels)');
			}
			view.destroy();
			texture.destroy();
		}
		Css.remove(sheet);
		dispose();
		tree.dispose();
	}
}
