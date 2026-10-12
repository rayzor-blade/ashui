import ashui.components.InputOtp;
import ashui.components.Size;
import ashui.core.render.Offscreen;
import ashui.css.Css;
import ashui.layout.LayoutTree;
import ashui.layout.Node;
import ashui.reactive.Owner;
import gpu.GpuTextureViewDescriptor;

/** Populated size variants must retain their glyphs at each display scale (git-bug e8a1b50). **/
class ComponentSizePixels {
	static function main():Void {
		ashui.theme.ThemeState.init(ashui.theme.themes.DefaultTheme.bundle(), Dark);
		// Use the gallery's TrueType font stack while the native CFF defect c2cfa79 is open.
		var sheet = Css.load('.ui-input-otp-slot { color: #ff0000; font-family: Menlo, Consolas, "Liberation Mono", monospace; }');
		var tree = new LayoutTree(), dispose = () -> {};
		var root = Owner.root(tree, stop -> {
			dispose = stop;
			return <div class="bg-background flex-col p-6 gap-4" width={360} height={260}>
				<for {size in [Size.Sm, Size.Md, Size.Lg]}>
					<input-otp size={size} length={4} separator={2} value="1234" />
				</for>
			</div>;
		});
		var renderer = Offscreen.create();
		for (scale in [1, 2]) {
			renderer.scale = scale;
			var width = 360 * scale, height = 260 * scale;
			var texture = renderer.createTexture(width, height), view = texture.createView(new GpuTextureViewDescriptor());
			renderer.render(root, view, 360, 260);
			var pixels = renderer.readRgba8(texture, width, height);
			var slots = Css.query(tree, root.node.id, ".ui-input-otp-slot");
			if (slots.length != 12) throw 'Expected all 12 OTP slots, got ${slots.length}';
			for (i in 0...slots.length) {
				var b = tree.getBounds(new Node(slots[i])), ink = 0;
				for (y in Std.int(b.y * scale)...Std.int((b.y + b.height) * scale))
					for (x in Std.int(b.x * scale)...Std.int((b.x + b.width) * scale)) {
						var p = (y * width + x) * 4;
						if (pixels.get(p) > 200 && pixels.get(p + 1) < 80 && pixels.get(p + 2) < 80) ink++;
					}
				if (ink < 10 * scale * scale) throw 'Missing glyph in slot $i at ${scale}x: $ink ink pixels';
				if (ink > b.width * b.height * scale * scale * 0.3) throw 'Oversized glyph in slot $i at ${scale}x: $ink ink pixels';
				Sys.println('ok   OTP slot $i paints its size variant at ${scale}x');
			}
			view.destroy(); texture.destroy();
		}
		if (Css.problems.length != 0) throw Css.problems.join("\n");
		Css.remove(sheet); dispose(); tree.dispose();
	}
}
