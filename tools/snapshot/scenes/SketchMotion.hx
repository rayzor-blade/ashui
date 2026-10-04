import ashui.debug.MotionRecorder;
import ashui.draw.Path;
import ashui.draw.Sketch;
import ashui.draw.Stroke;
import ashui.theme.ThemeState;
import ashui.theme.themes.DefaultTheme;
import ashui.types.Brush;
import ashui.types.Style;
import ashui.ui.Hxx.hxx;

/** Balls that bounce off the canvas's walls, each with a fading trail, a spinner turning by `t`, and a ring breathing by it. **/
class Bouncer implements Sketch {
	final balls:Array<{x:Float, y:Float, vx:Float, vy:Float, r:Float, color:Int, trail:Array<Float>}> = [];

	public function new() {}

	public function setup(ctx:SketchContext):Void {
		var colors = [0x7da8ff, 0xf59e0b, 0x22c55e, 0xef4444, 0xa855f7, 0x06b6d4];
		for (i in 0...6)
			balls.push({
				x: 40 + i * 50, y: 40 + (i * 37) % 120, vx: 120 + i * 25, vy: 80 + (i % 3) * 60, r: 10 + (i % 3) * 4,
				color: colors[i], trail: []
			});
	}

	public function draw(ctx:SketchContext, t:Float, dt:Float):Void {
		var p = ctx.painter();
		for (b in balls) {
			b.x += b.vx * dt;
			b.y += b.vy * dt;
			if (b.x < b.r || b.x > ctx.width - b.r) {
				b.vx = -b.vx;
				b.x = Math.max(b.r, Math.min(ctx.width - b.r, b.x));
			}
			if (b.y < b.r || b.y > ctx.height - b.r) {
				b.vy = -b.vy;
				b.y = Math.max(b.r, Math.min(ctx.height - b.r, b.y));
			}
			b.trail.push(b.x);
			b.trail.push(b.y);
			if (b.trail.length > 24)
				b.trail.splice(0, 2);
			var n = b.trail.length >> 1;
			for (i in 0...n)
				p.noStroke().fill(Brush.solid(b.color, 0.25 * (i + 1) / n)).circle(b.trail[i * 2], b.trail[i * 2 + 1], b.r * (0.4 + 0.6 * (i + 1) / n));
			p.fill(Brush.solid(b.color)).circle(b.x, b.y, b.r);
		}
		// A spinner: an arc turning at a turn a second.
		p.push().translate(ctx.width - 50, 50).rotate(t * Math.PI * 2);
		p.noFill().stroke(Brush.solid(0xffffff, 0.2), 4).circle(0, 0, 22);
		ctx.strokePath(new Path().arc(0, 0, 22, 0, Math.PI * 0.6), new Stroke(4, Round), Brush.solid(0x7da8ff));
		p.pop();
		// A ring breathing in and out.
		var r = 18 + 8 * Math.sin(t * Math.PI * 2);
		p.noFill().stroke(Brush.solid(0xf59e0b), 3).circle(50, ctx.height - 50, r);
	}
}

/**
	A sketch on a canvas, recorded frame by frame: balls bouncing with
	trails, a spinner and a breathing ring, drawn every frame on the
	animation scheduler's clock. Writes `.ashui/snapshots/motion/sketch/`.
**/
class SketchMotion {
	static function main() {
		ThemeState.init(DefaultTheme.bundle(), Dark);
		var page = ThemeState.get().color(Background);
		var sketch = new Bouncer();
		var build = () -> hxx('
			<div padding={20} width={520} height={340} flexDirection={Column}>
				<canvas width={480} height={300} sketch={sketch} class="rounded-xl bg-surface" />
			</div>
		');
		var result = MotionRecorder.record("sketch", 520, 340, build, {fps: 60, frames: 90, overlay: false, clear: page.rgb(), thumbs: 9});
		Sys.println(result.report.split("\n")[0]);
	}
}
