import ashui.core.render.Snapshot;
import ashui.draw.Affine;
import ashui.draw.DrawContext;
import ashui.draw.Path;
import ashui.draw.Stroke;
import ashui.theme.ThemeState;
import ashui.theme.themes.DefaultTheme;
import ashui.types.Brush;
import ashui.types.Style;
import ashui.ui.Hxx.hxx;

/**
	A canvas drawn through its DrawContext: strokes with each join and cap,
	dashes, curves, gradients, both fill rules on a star, a rotated and a
	faded shape, and an area chart. Writes `.ashui/snapshots/canvas.png`
	(`canvas-light` with `SCHEME=light`).
**/
class CanvasGallery {
	static function main() {
		var light = Sys.getEnv("SCHEME") == "light";
		ThemeState.init(DefaultTheme.bundle(), light ? Light : Dark);
		var theme = ThemeState.get();
		var page = theme.color(Background);
		var ink = theme.color(TextPrimary).rgb(), primary = theme.color(Primary).rgb(), muted = theme.color(TextTertiary).rgb();
		function draw(ctx:DrawContext) {
			// Joins: miter, round, bevel.
			for (i => join in [LineJoin.Miter, LineJoin.Round, LineJoin.Bevel]) {
				var x = 20 + i * 90;
				ctx.strokePath(new Path().moveTo(x, 80).lineTo(x + 30, 20).lineTo(x + 60, 80), new Stroke(12, Butt, join), Brush.solid(primary));
			}
			// Caps: butt, round, square, over a guide at the line's ends.
			for (i => cap in [LineCap.Butt, LineCap.Round, LineCap.Square]) {
				var y = 110 + i * 26;
				ctx.line(30, y, 230, y, new Stroke(12, cap), Brush.solid(ink, 0.85));
				ctx.line(30, y - 10, 30, y + 10, new Stroke(1), Brush.solid(0xef4444));
				ctx.line(230, y - 10, 230, y + 10, new Stroke(1), Brush.solid(0xef4444));
			}
			// Dashes, and hairlines down to a quarter of a pixel.
			ctx.line(30, 200, 230, 200, new Stroke(3, Round, Miter, 4, [12, 8]), Brush.solid(primary));
			for (i in 0...4)
				ctx.line(30, 215 + i * 8, 230, 215 + i * 8, new Stroke(1 / Math.pow(2, i)), Brush.solid(ink));
			// Curves.
			ctx.strokePath(new Path().moveTo(290, 80).cubicTo(320, -10, 380, 150, 420, 40).quadTo(440, 0, 470, 60), new Stroke(4, Round, Round),
				Brush.solid(0x22c55e));
			ctx.strokeCircle(330, 160, 34, new Stroke(2), Brush.solid(ink));
			ctx.fillCircle(330, 160, 26, Brush.radial(330, 152, 30).stop(0, 0xffffff).stop(1, primary));
			ctx.fillRect(390, 120, 90, 80, Brush.linear(390, 120, 480, 200).stop(0, 0xf59e0b).stop(0.5, 0xef4444).stop(1, 0x8b5cf6), 14);
			// A star by each fill rule.
			var star = new Path().moveTo(560, 20).lineTo(589, 110).lineTo(512, 54).lineTo(608, 54).lineTo(531, 110).close();
			ctx.fillPath(star, Brush.solid(0xf59e0b), NonZero);
			ctx.pushTransform(Affine.translation(96, 0));
			ctx.fillPath(star, Brush.solid(0xf59e0b), EvenOdd);
			ctx.popTransform();
			// Turned, and faded over what is under it.
			ctx.pushTransform(Affine.translation(600, 180).after(Affine.rotation(Math.PI / 6)));
			ctx.fillRect(-40, -25, 80, 50, Brush.solid(primary), 8);
			ctx.popTransform();
			ctx.pushOpacity(0.5);
			ctx.fillCircle(640, 200, 30, Brush.solid(0xef4444));
			ctx.popOpacity();
			// An area chart: a line, the area under it, a grid.
			var values = [12.0, 30, 22, 48, 40, 64, 58, 80, 72, 90];
			var x0 = 30.0, y0 = 400.0, w = 640.0, h = 120.0;
			for (i in 0...5)
				ctx.line(x0, y0 - i * h / 4, x0 + w, y0 - i * h / 4, new Stroke(1), Brush.solid(muted, 0.35));
			var line = new Path(), area = new Path();
			for (i => v in values) {
				var x = x0 + i * w / (values.length - 1), y = y0 - v / 100 * h;
				if (i == 0) {
					line.moveTo(x, y);
					area.moveTo(x, y0).lineTo(x, y);
				} else {
					line.lineTo(x, y);
					area.lineTo(x, y);
				}
			}
			area.lineTo(x0 + w, y0).close();
			ctx.fillPath(area, Brush.linear(0, y0 - h, 0, y0).stop(0, primary, 0.45).stop(1, primary, 0));
			ctx.strokePath(line, new Stroke(2.5, Round, Round), Brush.solid(primary));
			for (i => v in values)
				ctx.fillCircle(x0 + i * w / (values.length - 1), y0 - v / 100 * h, 3.5, Brush.solid(primary));
		}
		var build = () -> hxx('
			<div padding={24} width={760} height={470} flexDirection={Column}>
				<canvas width={700} height={420} draw={draw} />
			</div>
		');
		Snapshot.scene(light ? "canvas-light" : "canvas", 760, 470, build, page.rgb(), page.a, 2.0, 1.0);
	}
}
