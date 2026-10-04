import ashui.core.render.Snapshot;
import ashui.draw.Affine;
import ashui.draw.DrawContext;
import ashui.draw.Stroke;
import ashui.theme.ThemeState;
import ashui.theme.themes.DefaultTheme;
import ashui.types.Brush;
import ashui.types.Style;

/**
	Text drawn on a canvas: sizes and weights, the three alignments about one
	point and the four baselines on one line, each against a guide; a label
	turned about its middle; a title filled with a gradient. Writes
	`.ashui/snapshots/canvas-text.png` (`canvas-text-light` with
	`SCHEME=light`).
**/
class CanvasText {
	static function main() {
		var light = Sys.getEnv("SCHEME") == "light";
		ThemeState.init(DefaultTheme.bundle(), light ? Light : Dark);
		var theme = ThemeState.get();
		var page = theme.color(Background), ink = theme.color(TextPrimary).rgb(), muted = theme.color(TextTertiary).rgb(),
			primary = theme.color(Primary).rgb();
		function draw(ctx:DrawContext) {
			var guide = new Stroke(1), faint = Brush.solid(muted, 0.5);
			// Sizes and weights.
			var y = 40.0;
			for (row in [{size: 12.0, weight: 400}, {size: 16.0, weight: 500}, {size: 24.0, weight: 600}, {size: 36.0, weight: 700}]) {
				ctx.text('The quick brown fox ${Std.int(row.size)}px', 20, y, Brush.solid(ink), {size: row.size, weight: row.weight});
				y += row.size * 1.5 + 6;
			}
			// Alignments about one point, on a vertical guide.
			var cx = 520.0;
			ctx.line(cx, 20, cx, 130, guide, faint);
			ctx.text("Start", cx, 45, Brush.solid(ink), {size: 18, align: Start});
			ctx.text("Middle", cx, 80, Brush.solid(ink), {size: 18, align: Middle});
			ctx.text("End", cx, 115, Brush.solid(ink), {size: 18, align: End});
			// Baselines on one horizontal guide.
			var by = 220.0;
			ctx.line(20, by, 720, by, guide, faint);
			var x = 20.0;
			for (b in [{name: "Alphabetic", base: ashui.draw.GlyphOutlines.TextBaseline.Alphabetic}, {name: "Top", base: ashui.draw.GlyphOutlines.TextBaseline.Top}, {name: "Middle", base: ashui.draw.GlyphOutlines.TextBaseline.Middle}, {name: "Bottom", base: ashui.draw.GlyphOutlines.TextBaseline.Bottom}]) {
				ctx.text('${b.name} gy', x, by, Brush.solid(ink), {size: 22, baseline: b.base});
				x += ctx.measureText('${b.name} gy', {size: 22}).width + 30;
			}
			// A label turned about its middle.
			ctx.pushTransform(Affine.translation(620, 330).after(Affine.rotation(-Math.PI / 8)));
			ctx.text("Turned", 0, 0, Brush.solid(primary), {size: 28, weight: 700, align: Middle, baseline: Middle});
			ctx.popTransform();
			// A title filled with a gradient.
			ctx.text("Gradient title", 20, 330, Brush.linear(20, 0, 380, 0).stop(0, primary).stop(1, 0xec4899), {size: 44, weight: 700});
		}
		var build = () -> <div padding={20} width={780} height={400}><canvas width={740} height={360} draw={draw} /></div>;
		Snapshot.scene(light ? "canvas-text-light" : "canvas-text", 780, 400, build, page.rgb(), page.a, 2.0, 1.0);
	}
}
