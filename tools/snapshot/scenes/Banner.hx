import DashIcons.*;
import ashui.canvaskit.Environment;
import ashui.canvaskit.Geometry;
import ashui.canvaskit.OrbitCamera;
import ashui.canvaskit.SceneKit;
import ashui.components.ToggleSwitch;
import ashui.core.render.Snapshot;
import ashui.draw.DrawContext;
import ashui.draw.GlyphOutlines.TextAlignment;
import ashui.draw.GlyphOutlines.TextBaseline;
import ashui.draw.Path;
import ashui.draw.Stroke;
import ashui.draw3d.Light;
import ashui.draw3d.Material;
import ashui.layout.Element;
import ashui.math.Mat4;
import ashui.math.Vec3;
import ashui.reactive.Computed;
import ashui.reactive.Signal;
import ashui.theme.ThemeState;
import ashui.theme.themes.DefaultTheme;
import ashui.types.Brush;
import ashui.types.Notch;
import ashui.types.Style;

/**
	The README banner: an electric car's dashboard. The car (`BannerCar`)
	stands in a studio that follows the theme, under floating glass panels
	styled as ChimpMonk's editor styles its own, with a notched island
	(`Island`) hanging from the top edge. The gauges, the tyre diagram, the
	energy curve, the street map (`StreetMap`) and the callouts' leader lines
	are drawn on canvases.

	Writes `.ashui/snapshots/banner.png` (`banner-light` with
	`SCHEME=light`). With `MOTION=1` it records its half of the banner's
	12 s loop instead, to `motion/banner-loop` (`banner-loop-light`), and
	`banner-video.sh` joins the two halves into the README's GIF and an MP4.
**/
class Banner {
	static inline var WIDTH = 1600;
	static inline var HEIGHT = 820;

	/** How far the side columns reach in from the edges, which the callouts keep clear of. **/
	static inline var LEFT_PANEL = 340;
	static inline var RIGHT_PANEL = 364;

	/** Each half of the loop, light then dark, in seconds. **/
	static inline var HALF = 6.0;

	/**
		The recording's frame rate, and its frames: a lead-in while the car's
		textures upload, with the clock held at its start, then a half and half
		a second more, for the cross-fade. `banner-video.sh` skips the lead-in.
	**/
	static inline var FPS = 30;
	static inline var LEAD_IN = 12;
	static inline var FRAMES = LEAD_IN + 195;

	/** The camera's distance at rest, and how much further it draws back mid-turn. **/
	static inline var DISTANCE = 11.4;
	static inline var DRAW_BACK = 0.3;

	/** How far through its turn the car is at `t`: resting at each end of a half, easing through the middle. **/
	static function turning(t:Float):Float {
		var u = (t % HALF) / HALF;
		var c = Math.max(0, Math.min(1, (u - 0.18) / 0.64));
		return c * c * c * (c * (c * 6 - 15) + 10);
	}

	/** The car's turn at `t`: half a turn each half of the loop. **/
	static function turn(t:Float):Float
		return Math.PI * (Math.floor(t / HALF) + turning(t));

	/** The camera's distance at `t`: drawn back while the car turns. **/
	static function distance(t:Float):Float
		return DISTANCE * (1 + DRAW_BACK * Math.pow(Math.sin(Math.PI * turning(t)), 2));


	static function icon(markup:String, classes:String):Element {
		var svg = new ashui.ui.Svg(ashui.svg.Icon.fromMarkup(markup));
		ashui.css.Identity.of(svg.tree, svg.node.id).addClasses(classes.split(" "));
		return svg;
	}

	static function text(ctx:DrawContext, s:String, x:Float, y:Float, size:Float, weight:Int, color:Int, alpha = 1.0, ?align:TextAlignment) {
		ctx.text(s, x, y, Brush.solid(color, alpha), {size: size, weight: weight, align: align == null ? TextAlignment.Middle : align, baseline: TextBaseline.Middle});
	}

	/** A disc of light `size` pixels across: white, its alpha falling smoothly from the centre to nothing at the edge. **/
	static function glow(size:Int):ashui.types.Bitmap {
		var px = haxe.io.Bytes.alloc(size * size * 4);
		for (y in 0...size)
			for (x in 0...size) {
				var dx = (x + 0.5) / size * 2 - 1, dy = (y + 0.5) / size * 2 - 1;
				var r = Math.min(1, Math.sqrt(dx * dx + dy * dy));
				var o = (y * size + x) * 4;
				px.fill(o, 3, 255);
				px.set(o + 3, Std.int(Math.pow(1 - r * r * (3 - 2 * r), 1.6) * 255));
			}
		return ashui.types.Bitmap.fromBytes(ashui.core.render.Png.encode(size, size, px));
	}

	/** A smooth curve through `pts`, each span a cubic whose handles follow the neighbouring points. **/
	static function smoothThrough(path:Path, pts:Array<{x:Float, y:Float}>):Path {
		for (i in 0...pts.length - 1) {
			var p0 = pts[i == 0 ? 0 : i - 1], p1 = pts[i], p2 = pts[i + 1], p3 = pts[i + 2 < pts.length ? i + 2 : i + 1];
			path.cubicTo(p1.x + (p2.x - p0.x) / 6, p1.y + (p2.y - p0.y) / 6, p2.x - (p3.x - p1.x) / 6, p2.y - (p3.y - p1.y) / 6, p2.x, p2.y);
		}
		return path;
	}

	static function main() {
		var light = Sys.getEnv("SCHEME") == "light";
		ThemeState.init(DefaultTheme.bundle(), light ? Light : Dark);
		ashui.css.Css.add(ashui.css.CompiledCss.file("Banner.css"));
		var theme = ThemeState.get();
		var page = theme.color(Background);
		var ink = theme.color(TextPrimary).rgb(), muted = theme.color(TextTertiary).rgb(), primary = theme.color(Primary).rgb();
		var amber = 0xf59e0b, green = 0x22c55e, cyan = 0x22d3ee;
		var studio = light ? 0xe4e8ee : 0x161b23;

		var car = new BannerCar(0xb9bec6, 0.35, Sys.getEnv("TOON") != "0");

		// The timeline: one clock, in seconds, that every moving part reads. It loops every 12 s, light for the first half and
		// dark for the second, each half the same: the car rests, makes half a turn with the camera drawn back, and rests again.
		// Everything else cycles in periods that divide 12 s, so the loop and the hand-over between the halves are seamless.
		var motion = Sys.getEnv("MOTION") == "1";
		var start = motion && !light ? HALF : 0.0;
		var clock = Signal.make(start);
		inline function cycle(t:Float, period:Float):Float
			return Math.sin(Math.PI * 2 * t / period);
		// Far wider than the camera can see, even drawn back, so its edge never shows.
		var floor = Geometry.plane(600, 600, 1, new Material({baseColor: studio, roughness: 0.85}));
		var ringMaterial = new Material({baseColor: primary, emissive: primary, emissiveStrength: 1.2, unlit: true, alpha: 0.55, alphaMode: Blend});
		var rings = [Geometry.torus(2.95, 0.022, 160, 8, ringMaterial), Geometry.torus(3.18, 0.01, 160, 8, ringMaterial)];
		// A pool of the accent light under the car, wide enough to reach under the glass so the panels have colour to frost.
		var pool = Geometry.plane(9.5, 9.5, 1,
			new Material({baseColor: primary, baseColorTexture: glow(256), unlit: true, alpha: light ? 0.5 : 0.65, alphaMode: Blend}));
		var sky = BannerCar.studio(!light);
		function draw(ctx:ashui.draw.DrawContext) {
			ctx.drawMesh(floor);
			ctx.drawMesh(pool, Mat4.translation(new Vec3(0, 0.002, 0)));
			for (ring in rings)
				ctx.drawMesh(ring, Mat4.translation(new Vec3(0, 0.004, 0)));
			car.draw(ctx, turn(clock.get()));
		}
		var camera = new OrbitCamera(2.25, 0.38, DISTANCE, new Vec3(0.05, 0.62, 0.2), 0.5);
		var rig = [Directional(new Vec3(-0.35, -1, 0.3), 0xffffff, light ? 1.6 : 2.2)];

		/** Where a point of the scene lands in the banner, in layout units. **/
		function project(p:Vec3):{x:Float, y:Float} {
			var cam = camera.camera();
			var m = cam.projection(WIDTH / HEIGHT).mul(cam.view());
			var cx = m.get(0, 0) * p.x + m.get(1, 0) * p.y + m.get(2, 0) * p.z + m.get(3, 0);
			var cy = m.get(0, 1) * p.x + m.get(1, 1) * p.y + m.get(2, 1) * p.z + m.get(3, 1);
			var cw = m.get(0, 3) * p.x + m.get(1, 3) * p.y + m.get(2, 3) * p.z + m.get(3, 3);
			return {x: (cx / cw * 0.5 + 0.5) * WIDTH, y: (0.5 - cy / cw * 0.5) * HEIGHT};
		}

		function speedometer(ctx:DrawContext) {
			var cx = 142.0, cy = 112.0, r = 96.0, start = Math.PI * 0.75, sweep = Math.PI * 1.5, max = 200.0;
			// Cruising, the speed rising and falling round 86.
			var speed = 86 + 14 * cycle(clock.get(), 6) + 4 * cycle(clock.get(), 2);
			// A faint inner ring, the track, and the speed along it.
			ctx.strokePath(new Path().arc(cx, cy, r - 50, start, start + sweep), new Stroke(1, Round, Miter, 4, [2, 4]), Brush.solid(ink, 0.18));
			ctx.strokePath(new Path().arc(cx, cy, r, start, start + sweep), new Stroke(10, Round), Brush.solid(muted, 0.18));
			var end = start + sweep * speed / max;
			ctx.strokePath(new Path().arc(cx, cy, r, start, end), new Stroke(10, Round), Brush.linear(cx - r, cy + r, cx + r * 0.2, cy - r).stop(0, cyan).stop(1, primary));
			for (i in 0...41) {
				var a = start + sweep * i / 40, major = i % 4 == 0;
				var inner = r - (major ? 24 : 18), outer = r - 12;
				ctx.line(cx + Math.cos(a) * inner, cy + Math.sin(a) * inner, cx + Math.cos(a) * outer, cy + Math.sin(a) * outer,
					new Stroke(major ? 2 : 1, Round), Brush.solid(ink, i <= speed / max * 40 ? 0.7 : 0.22));
				if (i % 8 == 0)
					text(ctx, Std.string(Std.int(i * 5)), cx + Math.cos(a) * (r - 37), cy + Math.sin(a) * (r - 37), 10, 500, muted);
			}
			var ex = cx + Math.cos(end) * r, ey = cy + Math.sin(end) * r;
			ctx.fillCircle(ex, ey, 18, Brush.radial(ex, ey, 18).stop(0, primary, 0.5).stop(1, primary, 0));
			ctx.fillCircle(ex, ey, 6.5, Brush.solid(0xffffff));
			ctx.strokeCircle(ex, ey, 6.5, new Stroke(2.5), Brush.solid(primary));
			text(ctx, Std.string(Math.round(speed)), cx, cy - 4, 58, 600, ink);
			text(ctx, "km/h", cx, cy + 32, 12, 500, muted);
			// The drive mode, a pill in the gauge's open foot.
			ctx.fillRect(cx - 24, cy + 76, 48, 20, Brush.solid(green, 0.14), 10);
			text(ctx, "ECO", cx, cy + 86, 10.5, 700, green);
		}

		function battery(ctx:DrawContext) {
			var n = 26, gap = 3.0, w = (284 - gap * (n - 1)) / n, on = Math.round(n * 0.72);
			var fill = Brush.linear(0, 0, 284 * 0.72, 0).stop(0, 0x16a34a).stop(1, 0x84cc16);
			// Charging: a wave of light runs along the charge toward its edge every 2 s, and the edge's glow breathes.
			var wave = (clock.get() % 2) / 2 * (on + 6) - 3;
			for (i in 0...n) {
				ctx.fillRect(i * (w + gap), 2, w, 26, i < on ? fill : Brush.solid(muted, 0.16), 3);
				var lift = i < on ? Math.exp(-(i - wave) * (i - wave) / 3) : 0.0;
				if (lift > 0.02)
					ctx.fillRect(i * (w + gap), 2, w, 26, Brush.solid(0xffffff, 0.55 * lift), 3);
			}
			var edge = (on - 1) * (w + gap) + w / 2, breathe = 0.33 + 0.17 * cycle(clock.get(), 1.5);
			ctx.fillCircle(edge, 15, 18, Brush.radial(edge, 15, 18).stop(0, 0xa3e635, breathe).stop(1, 0xa3e635, 0));
			// The 80% charge limit.
			var limit = Math.round(n * 0.8) * (w + gap) - gap / 2;
			ctx.line(limit, 0, limit, 30, new Stroke(1.5, Round, Miter, 4, [2, 2]), Brush.solid(ink, 0.45));
		}

		function tyres(ctx:DrawContext) {
			var cx = 142.0, cy = 74.0;
			// The car from above: its body, the glass, and a wheel at each corner.
			ctx.fillRect(cx - 27, cy - 62, 54, 124, Brush.solid(ink, 0.06), 20);
			ctx.strokeRect(cx - 27, cy - 62, 54, 124, new Stroke(1.2), Brush.solid(ink, 0.25), 20);
			ctx.fillRect(cx - 19, cy - 24, 38, 50, Brush.solid(ink, 0.12), 9);
			ctx.line(cx - 19, cy - 2, cx + 19, cy - 2, new Stroke(1), Brush.solid(ink, 0.15));
			var wheels = [
				{x: -1, y: -1, bar: "2.4", temp: "31°", low: false},
				{x: 1, y: -1, bar: "2.4", temp: "31°", low: false},
				{x: -1, y: 1, bar: "2.1", temp: "29°", low: true},
				{x: 1, y: 1, bar: "2.4", temp: "30°", low: false}
			];
			for (wh in wheels) {
				var wx = cx + wh.x * 31, wy = cy + wh.y * 38;
				var colour = wh.low ? amber : ink;
				// The low tyre calls for attention: a ring spreading from it every 1.5 s.
				if (wh.low) {
					var u = (clock.get() % 1.5) / 1.5;
					ctx.strokeRect(wx - 5 - u * 9, wy - 12 - u * 9, 10 + u * 18, 24 + u * 18, new Stroke(1.5), Brush.solid(amber, 0.6 * (1 - u)), 3 + u * 9);
				}
				ctx.fillRect(wx - 5, wy - 12, 10, 24, Brush.solid(colour, wh.low ? 0.9 : 0.55), 3);
				var lx = cx + wh.x * 62;
				ctx.line(wx + wh.x * 9, wy, lx - wh.x * 4, wy, new Stroke(1, Round, Miter, 4, [2, 3]), Brush.solid(colour, 0.4));
				var align = wh.x < 0 ? TextAlignment.End : TextAlignment.Start;
				// The reading sits on the leader, level with the tyre's middle; its detail below. Digits sit a little low of the text's middle.
				text(ctx, wh.bar, lx, wy - 1.5, 17, 600, wh.low ? amber : ink, 1, align);
				text(ctx, wh.low ? "Low · " + wh.temp : "bar · " + wh.temp, lx, wy + 17, 10, 500, wh.low ? amber : muted, 1, align);
			}
		}

		function climate(ctx:DrawContext) {
			var cx = 154.0, cy = 114.0, r = 104.0, from = 16.0, to = 28.0;
			// Auto climate settling the cabin: the set point drifts and the dial follows, shown to the half degree.
			var value = 21.5 + 1.5 * cycle(clock.get(), 12);
			var warm = Brush.linear(cx - r, 0, cx + r, 0).stop(0, 0x38bdf8).stop(0.5, 0xa78bfa).stop(1, 0xfb923c);
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
			ctx.strokeCircle(kx, ky, 9, new Stroke(3), Brush.solid(0xa78bfa));
			var shown = Math.round(value * 2) / 2;
			text(ctx, Std.string(Math.floor(shown)) + "." + (shown % 1 == 0 ? "0" : "5") + "°", cx, cy - 48, 44, 600, ink);
			text(ctx, "Cabin · Auto", cx, cy - 15, 12, 500, muted);
			text(ctx, "16°", cx - r, cy + 13, 10, 500, muted);
			text(ctx, "28°", cx + r, cy + 13, 10, 500, muted);
		}

		function energy(ctx:DrawContext) {
			var values = [16.1, 15.2, 16.8, 14.3, 15.0, 13.4, 14.2];
			var w = 308.0, top = 20.0, bottom = 78.0, lo = 12.0, hi = 17.5;
			var pts = [for (i => v in values) {x: 10 + i * (w - 20) / (values.length - 1), y: top + (hi - v) / (hi - lo) * (bottom - top)}];
			for (i in 0...4)
				ctx.line(0, top + i * (bottom - top) / 3, w, top + i * (bottom - top) / 3, new Stroke(1), Brush.solid(ink, 0.06));
			var area = smoothThrough(new Path().moveTo(pts[0].x, bottom).lineTo(pts[0].x, pts[0].y), pts).lineTo(pts[pts.length - 1].x, bottom).close();
			ctx.fillPath(area, Brush.linear(0, top, 0, bottom).stop(0, primary, 0.3).stop(1, primary, 0));
			var avg = top + (hi - 14.6) / (hi - lo) * (bottom - top);
			ctx.line(0, avg, w, avg, new Stroke(1, Round, Miter, 4, [4, 4]), Brush.solid(muted, 0.6));
			text(ctx, "avg 14.6", 2, avg + 9, 9.5, 500, muted, 1, TextAlignment.Start);
			ctx.strokePath(smoothThrough(new Path().moveTo(pts[0].x, pts[0].y), pts), new Stroke(2.5, Round, Round), Brush.linear(0, 0, w, 0).stop(0, cyan).stop(1, primary));
			for (i in 0...pts.length - 1)
				ctx.fillCircle(pts[i].x, pts[i].y, 2.2, Brush.solid(primary, 0.7));
			var last = pts[pts.length - 1];
			ctx.fillCircle(last.x, last.y, 14, Brush.radial(last.x, last.y, 14).stop(0, primary, 0.45).stop(1, primary, 0));
			// Today's reading, live: a ring spreading from it every 1.5 s.
			var u = (clock.get() % 1.5) / 1.5;
			ctx.strokeCircle(last.x, last.y, 5 + u * 16, new Stroke(1.5), Brush.solid(primary, 0.7 * (1 - u)));
			ctx.fillCircle(last.x, last.y, 4.5, Brush.solid(0xffffff));
			ctx.strokeCircle(last.x, last.y, 4.5, new Stroke(2), Brush.solid(primary));
			ctx.fillRect(last.x - 50, last.y - 30, 42, 20, Brush.solid(primary), 10);
			text(ctx, "14.2", last.x - 29, last.y - 20, 11, 600, 0xffffff);
			for (i => day in ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"])
				text(ctx, day, pts[i].x, 92, 10, i == 6 ? 700 : 500, i == 6 ? primary : muted);
		}

		// Callouts: each a point on the car, a glass chip set off from it, and a line between. The points turn with the car;
		// a callout on the side of it fades as that side turns away, and follows the same point on the other side as that turns
		// to face the camera. Each chip sits on an ellipse round the car, out from its point, leaning the way `lean` says, so
		// the chips circle the car as it turns rather than landing on it; they keep clear of the side panels and the dock.
		var callouts = [
			{at: new Vec3(0.9, 0.7, -0.2), facing: new Vec3(1, 0, 0), lean: new Vec3(0, 1, 0), icon: LOCK, label: "Doors locked", note: "4 of 4"},
			{at: new Vec3(0.86, 0.92, 1.6), facing: new Vec3(1, 0, 0.25), lean: new Vec3(0, -0.8, 0), icon: BOLT, label: "Charge port", note: "11 kW"},
			{at: new Vec3(0.0, 1.45, 0.25), facing: new Vec3(0, 1, 0), lean: new Vec3(0.3, -1.5, 0), icon: THERMOMETER, label: "Cabin", note: "Auto"}
		];
		var chipWidth = 172.0, chipHeight = 40.0;
		var placed = Computed.make(() -> {
			var spin = Mat4.rotation(ashui.math.Quat.axisAngle(Vec3.UP, turn(clock.get())));
			var away = DISTANCE / camera.distance.get();
			var eye = camera.eye(), middle = project(new Vec3(0, 0.65, 0));
			var chips = [
				for (c in callouts) {
					var best = {x: 0.0, y: 0.0, seen: -1.0};
					for (side in (c.at.x == 0 ? [1.0] : [1.0, -1.0])) {
						var p = spin.transformPoint(new Vec3(c.at.x * side, c.at.y, c.at.z));
						var n = spin.transformDirection(new Vec3(c.facing.x * side, c.facing.y, c.facing.z)).normalize();
						var seen = n.dot(eye.sub(p).normalize());
						if (seen > best.seen) {
							var at = project(p);
							best = {x: at.x, y: at.y, seen: seen};
						}
					}
					var dx = (best.x - middle.x) / 300 + c.lean.x, dy = (best.y - middle.y) / 170 + c.lean.y;
					var len = Math.max(1e-6, Math.sqrt(dx * dx + dy * dy));
					var cx = Math.max(LEFT_PANEL + 16 + chipWidth / 2, Math.min(WIDTH - RIGHT_PANEL - 16 - chipWidth / 2, middle.x + dx / len * 400 * away));
					var cy = Math.max(72 + chipHeight / 2, Math.min(HEIGHT - 140 - chipHeight / 2, middle.y + dy / len * 235 * away));
					{x: best.x, y: best.y, cx: cx, cy: cy, opacity: Math.max(0, Math.min(1, (best.seen - 0.12) / 0.25))};
				}
			];
			// Chips that would overlap are pushed apart sideways, each half the overlap, then kept clear of the panels again.
			for (_ in 0...3)
				for (i in 0...chips.length)
					for (j in i + 1...chips.length) {
						var a = chips[i], b = chips[j];
						if (a.opacity < 0.05 || b.opacity < 0.05 || Math.abs(a.cy - b.cy) >= chipHeight + 8)
							continue;
						var gap = b.cx - a.cx, need = chipWidth + 12 - Math.abs(gap);
						if (need <= 0)
							continue;
						var way = gap != 0 ? (gap > 0 ? 1.0 : -1.0) : (b.x >= a.x ? 1.0 : -1.0);
						a.cx -= way * need / 2;
						b.cx += way * need / 2;
					}
			for (c in chips)
				c.cx = Math.max(LEFT_PANEL + 16 + chipWidth / 2, Math.min(WIDTH - RIGHT_PANEL - 16 - chipWidth / 2, c.cx));
			chips;
		});
		function leaders(ctx:DrawContext) {
			for (a in placed.get()) {
				if (a.opacity <= 0)
					continue;
				ctx.pushOpacity(a.opacity);
				var line = new Path().moveTo(a.x, a.y);
				if (Math.abs(a.cx - a.x) < chipWidth / 2 - 16) {
					// Straight up or down into the chip's nearer edge.
					line.lineTo(a.x, a.cy + (a.cy > a.y ? -chipHeight / 2 : chipHeight / 2));
				} else {
					// An elbow: out from the car on the diagonal, then level into the chip's nearer end.
					var end = a.cx + (a.cx > a.x ? -chipWidth / 2 : chipWidth / 2);
					line.lineTo(a.x + (end - a.x) * 0.35, a.cy).lineTo(end, a.cy);
				}
				ctx.strokePath(line, new Stroke(1.2, Round, Round), Brush.solid(primary, 0.75));
				ctx.fillCircle(a.x, a.y, 11, Brush.radial(a.x, a.y, 11).stop(0, primary, 0.45).stop(1, primary, 0));
				ctx.fillCircle(a.x, a.y, 3.5, Brush.solid(0xffffff));
				ctx.strokeCircle(a.x, a.y, 3.5, new Stroke(1.5), Brush.solid(primary));
				ctx.popOpacity();
			}
		}
		function callout(i:Int):Element {
			var c = callouts[i];
			return <div class="dash-chip flex flex-row items-center gap-2 pl-2 pr-3" position={Absolute} pointerEvents={PointerEvents.None}
				left={Computed.make(() -> placed.get()[i].cx - chipWidth / 2)} top={Computed.make(() -> placed.get()[i].cy - chipHeight / 2)}
				opacity={Computed.make(() -> placed.get()[i].opacity)} width={chipWidth} height={chipHeight}>
				<div class="dash-chip-icon flex items-center justify-center" width={26} height={26}>{icon(c.icon, "size-3.5")}</div>
				<text class="text-xs font-medium" flexGrow={1}>${c.label}</text>
				<text class="text-xs ink-2">${c.note}</text>
			</div>;
		}

		function header(title:String, right:Element):Element
			return <div class="dash-header flex flex-row items-center justify-between pl-4 pr-4" height={44}>
				<text>${title}</text>
				{right}
			</div>;

		function stat(label:String, value:String, unit:String):Element
			return <div flexDirection={Column} gap={2} flexGrow={1} flexBasis={0} alignItems={Center}>
				<text class="text-xs ink-3">${label}</text>
				<div flexDirection={Row} alignItems={End} gap={3}>
					<text class="text-sm font-semibold">${value}</text>
					<text class="text-xs ink-2">${unit}</text>
				</div>
			</div>;

		function gear(letter:String, on:Bool):Element
			return on ? <div class="dash-gear on flex items-center justify-center" width={22} height={22}><text>${letter}</text></div>
				: <div class="dash-gear flex items-center justify-center" width={22} height={22}><text>${letter}</text></div>;

		// The streets round King's Cross from OpenStreetMap, the route to the nearest free charger, and each charger.
		var streets = new StreetMap("../assets/map/kings-cross.json", "../assets/map/car-top.png");
		function map(ctx:DrawContext)
			streets.draw(ctx, 316, 100, 12, light, primary, [green, amber, muted], (clock.get() * 32) % 16);

		// A charging station: its name, how far and how fast, and how many of its chargers are free (0 many, 1 few, 2 none).
		function charger(name:String, detail:String, free:String, level:Int):Element {
			var state = level == 0 ? <text class="text-xs font-semibold good">${free}</text>
				: level == 1 ? <text class="text-xs font-semibold warn">${free}</text> : <text class="text-xs font-semibold ink-3">${free}</text>;
			return <div class="dash-row flex flex-row items-center gap-3 px-2" height={40}>
				<div class="dash-chip-icon flex items-center justify-center" width={32} height={32}>{icon(CHARGER, "size-4")}</div>
				<div flexDirection={Column} gap={1} flexGrow={1}>
					<text class="text-sm font-medium">${name}</text>
					<text class="text-xs ink-3">${detail}</text>
				</div>
				{state}
			</div>;
		}

		function round(markup:String, label:String, on:Bool):Element {
			var button = on ? <div class="dash-round on flex items-center justify-center" width={46} height={46}>{icon(markup, "size-5")}</div>
				: <div class="dash-round flex items-center justify-center" width={46} height={46}>{icon(markup, "size-5")}</div>;
			return <div flexDirection={Column} alignItems={Center} gap={6}>
				{button}
				<text class="text-xs ink-3">${label}</text>
			</div>;
		}

		function dockItem(markup:String, label:String, active:Bool):Element
			return active ? <div class="dash-item active flex flex-col items-center justify-center" gap={4} width={80} height={58}>
				{icon(markup, "size-5")}<text class="text-xs font-medium">${label}</text>
			</div> : <div class="dash-item flex flex-col items-center justify-center" gap={4} width={80} height={58}>
				{icon(markup, "size-5")}<text class="text-xs font-medium">${label}</text>
			</div>;

		var auto = Signal.make(true);
		var build = () -> <div width={WIDTH} height={HEIGHT}>
			<scene-kit camera={camera} lights={rig} environment={sky} environmentIntensity={light ? 0.9 : 1.0} background={studio} shadows={true}
				shadowStrength={light ? 0.45 : 0.6} shadowReach={4.5} draw={draw} widthPercent={1} heightPercent={1} />
			<canvas width={WIDTH} height={HEIGHT} draw={leaders} position={Absolute} left={0} top={0} pointerEvents={PointerEvents.None} />
			{callout(0)}{callout(1)}{callout(2)}

			<div flexDirection={Column} gap={16} position={Absolute} left={24} top={24} width={316}>
				<div class="dash-glass flex flex-col">
					{header("Drive", <div flexDirection={Row} gap={2}>{gear("P", false)}{gear("R", false)}{gear("N", false)}{gear("D", true)}</div>)}
					<div class="flex flex-col items-center px-4 pb-4 gap-3">
						<canvas width={284} height={210} draw={speedometer} />
						<div flexDirection={Row} alignItems={Center} widthPercent={1}>
							{stat("Trip", "38.4", "km")}<div class="dash-sep" width={1} height={28} />{stat("Average", "62", "km/h")}<div class="dash-sep" width={1} height={28} />{stat("Odometer", "12 480", "km")}
						</div>
					</div>
				</div>
				<div class="dash-glass flex flex-col">
					{header("Battery", <div class="charge flex flex-row items-center gap-1">{icon(BOLT, "size-3")}<text class="text-xs font-semibold">Charging · 11 kW</text></div>)}
					<div class="flex flex-col px-4 pb-4 gap-3">
						<div flexDirection={Row} alignItems={End} justifyContent={Justify.SpaceBetween}>
							<div flexDirection={Row} alignItems={End} gap={2}>
								<text class="text-3xl font-semibold">72</text>
								<text class="text-base ink-2" paddingBottom={3}>%</text>
							</div>
							<text class="text-sm ink-2" paddingBottom={3}>412 km range</text>
						</div>
						<canvas width={284} height={30} draw={battery} />
						<div flexDirection={Row} justifyContent={Justify.SpaceBetween}>
							<text class="text-xs ink-3">Full in 1 h 10 min</text>
							<text class="text-xs ink-3">Limit 80%</text>
						</div>
					</div>
				</div>
				<div class="dash-glass flex flex-col">
					{header("Tyres", <text class="text-xs ink-2">Pressure · temperature</text>)}
					<div class="flex flex-col px-4 pb-4">
						<canvas width={284} height={150} draw={tyres} />
					</div>
				</div>
			</div>

			<div flexDirection={Column} gap={12} position={Absolute} right={24} top={24} width={340}>
				<div class="dash-glass flex flex-col">
					{header("Climate", <div flexDirection={Row} alignItems={Center} gap={8}><text class="text-xs">Auto</text><toggle-switch checked={auto} /></div>)}
					<div class="flex flex-col items-center px-4 pb-4 gap-3">
						<canvas width={308} height={130} draw={climate} />
						<div flexDirection={Row} justifyContent={Justify.SpaceBetween} widthPercent={1}>
							{round(SNOW, "A/C", true)}{round(WIND, "Fan 3", false)}{round(SUN, "Defrost", false)}{round(SHIELD, "Guard", true)}
						</div>
					</div>
				</div>
				<div class="dash-glass flex flex-col">
					{header("Energy", <text class="text-xs ink-2">kWh / 100 km</text>)}
					<div class="flex flex-col px-4 pb-4 gap-1">
						<canvas width={308} height={100} draw={energy} />
						<div flexDirection={Row} justifyContent={Justify.SpaceBetween}>
							<text class="text-xs ink-3">This week</text>
							<text class="text-xs good">6% under last week</text>
						</div>
					</div>
				</div>
				<div class="dash-glass flex flex-col">
					{header("Nearby chargers", <text class="text-xs ink-2">On route</text>)}
					<div class="flex flex-col px-3 pb-3 gap-1">
						<div width={316} height={100} marginBottom={4}>
							<canvas width={316} height={100} draw={map} />
							<!-- Over the map, so its shadow falls on the streets as a recess's would. -->
							<div class="map-inset" position={Absolute} left={0} top={0} width={316} height={100} pointerEvents={PointerEvents.None} />
						</div>
						{charger("Granary Square", "1.3 km · 150 kW", "4 free", 0)}
						{charger("Coal Drops Yard", "1.6 km · 50 kW", "1 free", 1)}
					</div>
				</div>
			</div>

			<div position={Absolute} left={0} right={0} bottom={24} flexDirection={Row} justifyContent={Justify.Center}>
				<div class="dash-dock flex flex-row items-center gap-1 p-2">
					{dockItem(NAVIGATE, "Navigate", false)}{dockItem(MUSIC, "Media", false)}{dockItem(CAR, "Vehicle", true)}
					{dockItem(CHARGER, "Charging", false)}{dockItem(CAMERA, "Camera", false)}{dockItem(PHONE, "Phone", false)}
					{dockItem(USER, "Profile", false)}
					<div class="dash-sep" width={1} height={30} marginLeft={4} marginRight={4} />
					{dockItem(MORE, "More", false)}
				</div>
			</div>
			{Island.build(WIDTH, clock)}
		</div>;
		if (motion) {
			// Each half recorded on its own, from where it starts on the clock, half a second past its end so the halves can be
			// cross-faded where they meet. The pointer opens the island's items in turn while the car turns, then leaves.
			var script = light ? [15 => "music", 55 => "weather", 90 => "wifi", 110 => "time", 140 => ""] : [15 => "weather", 50 => "music", 85 => "signal",
				110 => "drive", 140 => ""];
			var result = ashui.debug.MotionRecorder.record(light ? "banner-loop-light" : "banner-loop", WIDTH, HEIGHT, build, {
				fps: FPS, frames: FRAMES, minFrames: FRAMES, settle: 0.5, scale: 2.0, clear: page.rgb(), overlay: false, tree: false, plain: false,
				before: (frame, tree, root) -> {
					var t = start + Math.max(0, frame - LEAD_IN) / FPS;
					clock.set(t);
					camera.distance.set(distance(t));
					if (!script.exists(frame - LEAD_IN))
						return;
					var id = script.get(frame - LEAD_IN);
					if (id == "") {
						ashui.input.Pointer.move(tree, WIDTH / 2, HEIGHT - 300);
						return;
					}
					for (node in tree.order()) {
						var identity = ashui.css.Identity.of(tree, node);
						if (identity != null && identity.id == "island-" + id) {
							var b = tree.getBounds(new ashui.layout.Node(node));
							ashui.input.Pointer.move(tree, b.x + b.width / 2, b.y + b.height / 2);
						}
					}
				}
			});
			Sys.println(result.report.split("\n")[0]);
		} else
			// In a window the scene is at rest and the user moves it: drag to turn the camera round the car, scroll to come nearer.
			Snapshot.scene(light ? "banner-light" : "banner", WIDTH, HEIGHT, build, page.rgb(), page.a, 2.0, 1.0);
		for (p in ashui.css.Css.problems)
			Sys.println("css: " + p);
	}
}
