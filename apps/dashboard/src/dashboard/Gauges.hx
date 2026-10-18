package dashboard;

import ashui.draw.DrawContext;
import ashui.draw.GlyphOutlines.TextAlignment;
import ashui.draw.Path;
import ashui.draw.Stroke;
import ashui.types.Brush;
import dashboard.Ink.*;

/**
	What the dashboard draws on canvases: the speedometer, the charge, the tyres, the climate dial and the week's
	consumption. Each is a function from what it shows to a draw, which reads the signals it shows, so it is drawn again
	when they change and not otherwise.
**/
class Gauges {
	/** A smooth curve through `pts`, each span a cubic whose handles follow the neighbouring points. **/
	public static function smoothThrough(path:Path, pts:Array<{x:Float, y:Float}>):Path {
		for (i in 0...pts.length - 1) {
			var p0 = pts[i == 0 ? 0 : i - 1], p1 = pts[i], p2 = pts[i + 1], p3 = pts[i + 2 < pts.length ? i + 2 : i + 1];
			path.cubicTo(p1.x + (p2.x - p0.x) / 6, p1.y + (p2.y - p0.y) / 6, p2.x - (p3.x - p1.x) / 6, p2.y - (p3.y - p1.y) / 6, p2.x, p2.y);
		}
		return path;
	}

	public static function speedometer(m:Model):DrawContext->Void
		return ctx -> {
			follow();
			var ink = ink(), muted = muted(), primary = primary();
			var cx = 142.0, cy = 112.0, r = 96.0, start = Math.PI * 0.75, sweep = Math.PI * 1.5;
			var miles = m.miles.get();
			var max = miles ? 125.0 : 200.0;
			var speed = Math.min(max, m.shown(m.speed.get()));
			// A faint inner ring, the track, and the speed along it.
			ctx.strokePath(new Path().arc(cx, cy, r - 50, start, start + sweep), new Stroke(1, Round, Miter, 4, [2, 4]), Brush.solid(ink, 0.18));
			ctx.strokePath(new Path().arc(cx, cy, r, start, start + sweep), new Stroke(10, Round), Brush.solid(muted, 0.18));
			var end = start + sweep * speed / max;
			if (speed > 0.4)
				ctx.strokePath(new Path().arc(cx, cy, r, start, end), new Stroke(10, Round), Brush.linear(cx - r, cy + r, cx + r * 0.2, cy - r).stop(0, CYAN).stop(1, primary));
			for (i in 0...41) {
				var a = start + sweep * i / 40, major = i % 4 == 0;
				var inner = r - (major ? 24 : 18), outer = r - 12;
				ctx.line(cx + Math.cos(a) * inner, cy + Math.sin(a) * inner, cx + Math.cos(a) * outer, cy + Math.sin(a) * outer,
					new Stroke(major ? 2 : 1, Round), Brush.solid(ink, i <= speed / max * 40 ? 0.7 : 0.22));
				if (i % 8 == 0)
					text(ctx, Std.string(Math.round(i * max / 40)), cx + Math.cos(a) * (r - 37), cy + Math.sin(a) * (r - 37), 10, 500, muted);
			}
			var ex = cx + Math.cos(end) * r, ey = cy + Math.sin(end) * r;
			ctx.fillCircle(ex, ey, 18, Brush.radial(ex, ey, 18).stop(0, primary, 0.5).stop(1, primary, 0));
			ctx.fillCircle(ex, ey, 6.5, Brush.solid(0xffffff));
			ctx.strokeCircle(ex, ey, 6.5, new Stroke(2.5), Brush.solid(primary));
			text(ctx, Std.string(Math.round(speed)), cx, cy - 4, 58, 600, ink);
			text(ctx, m.unit(), cx, cy + 32, 12, 500, muted);
			// The mode, a pill in the gauge's open foot.
			var mode = switch m.gear.get() {
				case D: "ECO";
				case R: "REVERSE";
				case N: "NEUTRAL";
				case P: "PARKED";
			}
			var tone = m.gear.get() == D ? GREEN : m.gear.get() == R ? AMBER : muted;
			var w = m.gear.get() == D ? 48.0 : 74.0;
			ctx.fillRect(cx - w / 2, cy + 76, w, 20, Brush.solid(tone, 0.14), 10);
			text(ctx, mode, cx, cy + 86, 10.5, 700, tone);
		};

	public static function battery(m:Model):DrawContext->Void
		return ctx -> {
			follow();
			var ink = ink(), muted = muted();
			var n = 26, gap = 3.0, w = (284 - gap * (n - 1)) / n;
			var charge = m.charge.get(), on = Math.round(n * charge / 100);
			var fill = Brush.linear(0, 0, 284 * charge / 100, 0).stop(0, 0x16a34a).stop(1, 0x84cc16);
			var charging = m.charging.get();
			// Charging: a wave of light runs along the charge toward its edge every 2 s, and the edge's glow breathes.
			var wave = charging ? (m.clock.get() % 2) / 2 * (on + 6) - 3 : -10.0;
			for (i in 0...n) {
				ctx.fillRect(i * (w + gap), 2, w, 26, i < on ? fill : Brush.solid(muted, 0.16), 3);
				var lift = i < on && charging ? Math.exp(-(i - wave) * (i - wave) / 3) : 0.0;
				if (lift > 0.02)
					ctx.fillRect(i * (w + gap), 2, w, 26, Brush.solid(0xffffff, 0.55 * lift), 3);
			}
			if (charging && on > 0) {
				var edge = (on - 1) * (w + gap) + w / 2, breathe = 0.33 + 0.17 * Math.sin(Math.PI * 2 * m.clock.get() / 1.5);
				ctx.fillCircle(edge, 15, 18, Brush.radial(edge, 15, 18).stop(0, 0xa3e635, breathe).stop(1, 0xa3e635, 0));
			}
			// The charge limit.
			var limit = Math.round(n * m.limit.get() / 100) * (w + gap) - gap / 2;
			ctx.line(limit, 0, limit, 30, new Stroke(1.5, Round, Miter, 4, [2, 2]), Brush.solid(ink, 0.45));
		};

	public static function tyres(m:Model):DrawContext->Void
		return ctx -> {
			follow();
			var ink = ink(), muted = muted();
			var cx = 142.0, cy = 74.0;
			// The car from above: its body, the glass, and a wheel at each corner.
			ctx.fillRect(cx - 27, cy - 62, 54, 124, Brush.solid(ink, 0.06), 20);
			ctx.strokeRect(cx - 27, cy - 62, 54, 124, new Stroke(1.2), Brush.solid(ink, 0.25), 20);
			ctx.fillRect(cx - 19, cy - 24, 38, 50, Brush.solid(ink, 0.12), 9);
			ctx.line(cx - 19, cy - 2, cx + 19, cy - 2, new Stroke(1), Brush.solid(ink, 0.15));
			var pressure = m.miles.get() ? [34.8, 34.8, 30.5, 34.8] : [2.4, 2.4, 2.1, 2.4];
			var unit = m.miles.get() ? "psi" : "bar";
			var wheels = [
				{x: -1, y: -1, temp: "31°", low: false},
				{x: 1, y: -1, temp: "31°", low: false},
				{x: -1, y: 1, temp: "29°", low: true},
				{x: 1, y: 1, temp: "30°", low: false}
			];
			for (i => wh in wheels) {
				var wx = cx + wh.x * 31, wy = cy + wh.y * 38;
				var colour = wh.low ? AMBER : ink;
				// The low tyre calls for attention: a ring spreading from it every 1.5 s.
				if (wh.low) {
					var u = (m.clock.get() % 1.5) / 1.5;
					ctx.strokeRect(wx - 5 - u * 9, wy - 12 - u * 9, 10 + u * 18, 24 + u * 18, new Stroke(1.5), Brush.solid(AMBER, 0.6 * (1 - u)), 3 + u * 9);
				}
				ctx.fillRect(wx - 5, wy - 12, 10, 24, Brush.solid(colour, wh.low ? 0.9 : 0.55), 3);
				var lx = cx + wh.x * 62;
				ctx.line(wx + wh.x * 9, wy, lx - wh.x * 4, wy, new Stroke(1, Round, Miter, 4, [2, 3]), Brush.solid(colour, 0.4));
				var align = wh.x < 0 ? TextAlignment.End : TextAlignment.Start;
				var reading = m.miles.get() ? Std.string(Math.round(pressure[i] * 10) / 10) : Std.string(pressure[i]);
				text(ctx, reading, lx, wy - 1.5, 17, 600, wh.low ? AMBER : ink, 1, align);
				text(ctx, wh.low ? "Low · " + wh.temp : unit + " · " + wh.temp, lx, wy + 17, 10, 500, wh.low ? AMBER : muted, 1, align);
			}
		};

	public static function climate(m:Model):DrawContext->Void
		return ctx -> {
			follow();
			var ink = ink(), muted = muted();
			var cx = 154.0, cy = 114.0, r = 104.0, from = 16.0, to = 28.0;
			var value = m.target.get();
			var warm = Brush.linear(cx - r, 0, cx + r, 0).stop(0, 0x38bdf8).stop(0.5, VIOLET).stop(1, 0xfb923c);
			ctx.pushOpacity(0.22);
			ctx.strokePath(new Path().arc(cx, cy, r, Math.PI, Math.PI * 2), new Stroke(8, Round), warm);
			ctx.popOpacity();
			var at = Math.PI + Math.PI * (value - from) / (to - from);
			ctx.strokePath(new Path().arc(cx, cy, r, Math.PI, at), new Stroke(8, Round), warm);
			for (i in 0...25) {
				var a = Math.PI + Math.PI * i / 24;
				var inner = r - (i % 4 == 0 ? 20 : 15), outer = r - 10;
				ctx.line(cx + Math.cos(a) * inner, cy + Math.sin(a) * inner, cx + Math.cos(a) * outer, cy + Math.sin(a) * outer,
					new Stroke(i % 4 == 0 ? 1.6 : 1, Round), Brush.solid(ink, i % 4 == 0 ? 0.45 : 0.2));
			}
			var kx = cx + Math.cos(at) * r, ky = cy + Math.sin(at) * r;
			ctx.fillCircle(kx, ky + 2, 13, Brush.radial(kx, ky + 2, 13).stop(0, 0x000000, 0.25).stop(1, 0x000000, 0));
			ctx.fillCircle(kx, ky, 9, Brush.solid(0xffffff));
			ctx.strokeCircle(kx, ky, 9, new Stroke(3), Brush.solid(VIOLET));
			var shown = Math.round(value * 2) / 2;
			text(ctx, Std.string(Math.floor(shown)) + "." + (shown % 1 == 0 ? "0" : "5") + "°", cx, cy - 48, 44, 600, ink);
			text(ctx, m.auto.get() ? "Cabin · Auto" : "Cabin · Manual", cx, cy - 15, 12, 500, muted);
			text(ctx, "16°", cx - r, cy + 13, 10, 500, muted);
			text(ctx, "28°", cx + r, cy + 13, 10, 500, muted);
		};

	public static function energy(m:Model):DrawContext->Void
		return ctx -> {
			follow();
			var ink = ink(), muted = muted(), primary = primary();
			var values = [16.1, 15.2, 16.8, 14.3, 15.0, 13.4, 14.2];
			var w = 308.0, top = 20.0, bottom = 78.0, lo = 12.0, hi = 17.5;
			var pts = [for (i => v in values) {x: 10 + i * (w - 20) / (values.length - 1), y: top + (hi - v) / (hi - lo) * (bottom - top)}];
			for (i in 0...4)
				ctx.line(0, top + i * (bottom - top) / 3, w, top + i * (bottom - top) / 3, new Stroke(1), Brush.solid(ink, 0.06));
			var area = smoothThrough(new Path().moveTo(pts[0].x, bottom).lineTo(pts[0].x, pts[0].y), pts).lineTo(pts[pts.length - 1].x, bottom).close();
			ctx.fillPath(area, Brush.linear(0, top, 0, bottom).stop(0, primary, 0.3).stop(1, primary, 0));
			var avg = top + (hi - 14.6) / (hi - lo) * (bottom - top);
			ctx.line(0, avg, w, avg, new Stroke(1, Round, Miter, 4, [4, 4]), Brush.solid(muted, 0.6));
			text(ctx, "avg " + Std.string(Math.round(m.consumption(14.6) * 10) / 10), 2, avg + 9, 9.5, 500, muted, 1, TextAlignment.Start);
			ctx.strokePath(smoothThrough(new Path().moveTo(pts[0].x, pts[0].y), pts), new Stroke(2.5, Round, Round), Brush.linear(0, 0, w, 0).stop(0, CYAN).stop(1, primary));
			for (i in 0...pts.length - 1)
				ctx.fillCircle(pts[i].x, pts[i].y, 2.2, Brush.solid(primary, 0.7));
			var last = pts[pts.length - 1];
			ctx.fillCircle(last.x, last.y, 14, Brush.radial(last.x, last.y, 14).stop(0, primary, 0.45).stop(1, primary, 0));
			ctx.fillCircle(last.x, last.y, 4.5, Brush.solid(0xffffff));
			ctx.strokeCircle(last.x, last.y, 4.5, new Stroke(2), Brush.solid(primary));
			ctx.fillRect(last.x - 50, last.y - 30, 42, 20, Brush.solid(primary), 10);
			text(ctx, Std.string(Math.round(m.consumption(14.2) * 10) / 10), last.x - 29, last.y - 20, 11, 600, 0xffffff);
			for (i => day in ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"])
				text(ctx, day, pts[i].x, 92, 10, i == 6 ? 700 : 500, i == 6 ? primary : muted);
		};
}
