import ashui.core.render.Snapshot;
import ashui.draw.Affine;
import ashui.draw.DrawContext;
import ashui.draw.Stroke;
import ashui.theme.ThemeState;
import ashui.theme.themes.DefaultTheme;
import ashui.types.Bitmap;
import ashui.types.Brush;
import ashui.types.Style;

/**
	Clips on a canvas: stripes kept inside a rounded rectangle, a circle and
	an ellipse; a circle inside a rectangle, nested; a clip turned with
	what it holds; a photo kept in a circle, as an avatar; text cut by a
	rectangle. Each clip's outline is drawn faintly over it. Writes
	`.ashui/snapshots/canvas-clip.png` (`canvas-clip-light` with
	`SCHEME=light`).
**/
class CanvasClip {
	static function main() {
		var light = Sys.getEnv("SCHEME") == "light";
		ThemeState.init(DefaultTheme.bundle(), light ? Light : Dark);
		var theme = ThemeState.get();
		var page = theme.color(Background), ink = theme.color(TextPrimary).rgb(), muted = theme.color(TextTertiary).rgb(),
			primary = theme.color(Primary).rgb();
		var avatar = Bitmap.embed("assets/avatar.jpg");
		var palette = [0x3b82f6, 0x22c55e, 0xf59e0b, 0xef4444, 0xa855f7];
		function stripes(ctx:DrawContext, x:Float, y:Float, w:Float, h:Float) {
			var i = 0, at = x - h;
			while (at < x + w) {
				var path = new ashui.draw.Path().moveTo(at, y + h).lineTo(at + h, y).lineTo(at + h + 14, y).lineTo(at + 14, y + h).close();
				ctx.fillPath(path, Brush.solid(palette[i++ % palette.length]));
				at += 28;
			}
		}
		function draw(ctx:DrawContext) {
			var outline = new Stroke(1), faint = Brush.solid(muted, 0.6);
			// Kept inside a rounded rectangle, a circle and an ellipse.
			ctx.pushClipRect(20, 20, 160, 120, 24);
			stripes(ctx, 0, 0, 220, 160);
			ctx.popClip();
			ctx.strokeRect(20, 20, 160, 120, outline, faint, 24);
			ctx.pushClipCircle(280, 80, 60);
			stripes(ctx, 200, 0, 180, 160);
			ctx.popClip();
			ctx.pushClipEllipse(450, 80, 70, 45);
			stripes(ctx, 360, 0, 200, 160);
			ctx.popClip();
			// A circle inside a rectangle: kept where both are.
			ctx.pushClipRect(560, 30, 100, 100);
			ctx.pushClipCircle(660, 80, 60);
			stripes(ctx, 540, 0, 200, 160);
			ctx.popClip();
			ctx.popClip();
			ctx.strokeRect(560, 30, 100, 100, outline, faint);
			ctx.strokeCircle(660, 80, 60, outline, faint);
			// A clip turned with what it holds.
			ctx.pushTransform(Affine.translation(110, 260).after(Affine.rotation(0.35)));
			ctx.pushClipRect(-70, -50, 140, 100, 12);
			stripes(ctx, -120, -80, 240, 160);
			ctx.popClip();
			ctx.strokeRect(-70, -50, 140, 100, outline, faint, 12);
			ctx.popTransform();
			// A photo kept in a circle.
			ctx.pushClipCircle(290, 260, 60);
			ctx.image(avatar, 230, 200, 120, 120);
			ctx.popClip();
			// Text cut by a rectangle: the top half of each glyph.
			ctx.pushClipRect(390, 200, 300, 47);
			ctx.text("Clipped", 400, 280, Brush.solid(primary), {size: 64, weight: 700});
			ctx.popClip();
			ctx.text("Clipped", 400, 280, Brush.solid(ink, 0.15), {size: 64, weight: 700});
			ctx.line(390, 247, 690, 247, outline, faint);
		}
		var build = () -> <div padding={20}><canvas width={700} height={340} draw={draw} /></div>;
		Snapshot.scene(light ? "canvas-clip-light" : "canvas-clip", 740, 380, build, page.rgb(), page.a, 2.0, 1.0);
	}
}
