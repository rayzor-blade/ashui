package dashboard;

import ashui.components.Slider;
import ashui.components.ToggleSwitch;
import ashui.draw.DrawContext;
import ashui.draw.Path;
import ashui.draw.Stroke;
import ashui.icons.Remix;
import ashui.layout.Element;
import ashui.reactive.Computed;
import ashui.types.Brush;
import ashui.types.Style;
import dashboard.Ink.*;
import dashboard.Widgets.*;

/**
	The Charging page: the charge as a ring, with the limit it will stop at, which the slider moves; the charge's curve, which
	slows toward the top as a real one does; whether it is charging, which the key starts and stops; and the stations
	near, to drive to.
**/
class ChargingView {
	final m:Model;

	public function new(m:Model)
		this.m = m;

	function ring():DrawContext->Void
		return ctx -> {
			follow();
			var ink = ink(), muted = muted();
			var cx = 130.0, cy = 130.0, r = 104.0, start = Math.PI * 0.75, sweep = Math.PI * 1.5;
			var charge = m.charge.get(), limit = m.limit.get();
			ctx.strokePath(new Path().arc(cx, cy, r, start, start + sweep), new Stroke(16, Round), Brush.solid(muted, 0.16));
			var end = start + sweep * charge / 100;
			if (charge > 0.5)
				ctx.strokePath(new Path().arc(cx, cy, r, start, end), new Stroke(16, Round), Brush.linear(cx - r, cy + r, cx + r, cy - r).stop(0, 0x16a34a).stop(1, 0x84cc16));
			// The limit, a tick across the ring.
			var a = start + sweep * limit / 100;
			ctx.line(cx + Math.cos(a) * (r - 14), cy + Math.sin(a) * (r - 14), cx + Math.cos(a) * (r + 14), cy + Math.sin(a) * (r + 14), new Stroke(3, Round),
				Brush.solid(ink, 0.85));
			if (m.charging.get()) {
				var pulse = 0.5 + 0.5 * Math.sin(Math.PI * 2 * m.clock.get() / 1.5);
				var ex = cx + Math.cos(end) * r, ey = cy + Math.sin(end) * r;
				ctx.fillCircle(ex, ey, 20, Brush.radial(ex, ey, 20).stop(0, 0xa3e635, 0.25 + 0.3 * pulse).stop(1, 0xa3e635, 0));
			}
			text(ctx, Std.string(Math.floor(charge)), cx - 8, cy - 8, 64, 600, ink);
			text(ctx, "%", cx + 52, cy + 4, 20, 500, muted);
			text(ctx, m.charging.get() ? "Charging" : charge >= limit ? "At the limit" : "Paused", cx, cy + 44, 13, 500, m.charging.get() ? GREEN : muted);
		};

	/** Power against the charge: flat to about 55%, then tapering toward the limit; the charge now marked on it. **/
	function curve():DrawContext->Void
		return ctx -> {
			follow();
			var ink = ink(), muted = muted(), primary = primary();
			var w = 360.0, top = 12.0, bottom = 110.0, kw = 11.0;
			function power(p:Float):Float
				return p < 55 ? 1.0 : Math.max(0.12, 1 - Math.pow((p - 55) / 55, 1.6));
			var line = new Path();
			for (i in 0...61) {
				var p = i / 60 * 100;
				var x = p / 100 * w, y = bottom - (bottom - top) * power(p);
				if (i == 0)
					line.moveTo(x, y);
				else
					line.lineTo(x, y);
			}
			for (i in 0...3)
				ctx.line(0, top + i * (bottom - top) / 2, w, top + i * (bottom - top) / 2, new Stroke(1), Brush.solid(ink, 0.06));
			ctx.strokePath(line, new Stroke(2.5, Round, Round), Brush.linear(0, 0, w, 0).stop(0, CYAN).stop(1, primary));
			var x = m.charge.get() / 100 * w, y = bottom - (bottom - top) * power(m.charge.get());
			ctx.line(x, top, x, bottom, new Stroke(1, Round, Miter, 4, [3, 3]), Brush.solid(muted, 0.6));
			ctx.fillCircle(x, y, 11, Brush.radial(x, y, 11).stop(0, primary, 0.5).stop(1, primary, 0));
			ctx.fillCircle(x, y, 4.5, Brush.solid(0xffffff));
			ctx.strokeCircle(x, y, 4.5, new Stroke(2), Brush.solid(primary));
			text(ctx, Std.string(Math.round(kw * power(m.charge.get()) * 10) / 10) + " kW", Math.min(w - 30, Math.max(30, x)), top - 1, 10, 600, ink);
			text(ctx, "0%", 8, bottom + 10, 10, 500, muted);
			text(ctx, "50%", w / 2, bottom + 10, 10, 500, muted);
			text(ctx, "100%", w - 12, bottom + 10, 10, 500, muted);
		};

	function station(i:Int):Element {
		var c = Model.CHARGERS[i];
		var level = c.free == 0 ? 2 : c.free < 3 ? 1 : 0;
		var free = c.free == 0 ? "Full" : c.free + " of " + c.of + " free";
		var state = level == 0 ? <text class="text-xs font-semibold good">${free}</text>
			: level == 1 ? <text class="text-xs font-semibold warn">${free}</text> : <text class="text-xs font-semibold ink-3">${free}</text>;
		var go = press(<div class="dash-chip flex items-center justify-center" width={36} height={36}>{icon(Remix.NAVIGATION_FILL, "size-4")}</div>, () -> {
			m.navigateTo(i);
			m.tab.set(Navigate);
		});
		return <div class="dash-tile flex flex-row items-center gap-3 px-3" height={60}>
			<div class="dash-chip-icon flex items-center justify-center" width={36} height={36}>{icon(Remix.CHARGING_PILE_2_LINE, "size-5")}</div>
			<div flexDirection={Column} gap={2} flexGrow={1}>
				<text class="text-sm font-semibold">${c.name}</text>
				<text class="text-xs ink-3">${live(() -> Std.string(Math.round(m.distance(c.km) * 10) / 10) + " " + m.distanceUnit() + " · " + c.kw + " kW")}</text>
			</div>
			{state}
			{go}
		</div>;
	}

	function toggleRow(label:String, detail:String, state:ashui.reactive.Signal<Bool>):Element
		return <div class="flex flex-row items-center justify-between">
			<div flexDirection={Column} gap={2}>
				<text class="text-sm font-medium">${label}</text>
				<text class="text-xs ink-3">${detail}</text>
			</div>
			<toggle-switch checked={state} />
		</div>;

	public function build():Element {
		var limit = <slider value={m.limit} min={50} max={100} step={5} onChange={v -> m.limit.set(v)} />;
		var scheduled = ashui.reactive.Signal.make(true);
		var key = flag(press(<div class="dash-go flex flex-row items-center justify-center gap-2" height={44}>{icon(Remix.FLASHLIGHT_FILL, "size-4")}
			<text class="text-sm font-semibold">${m.charging.get() ? "Stop charging" : "Start charging"}</text></div>, () -> {
				if (m.charge.get() >= m.limit.get())
					m.limit.set(Math.min(100, m.limit.get() + 10));
				m.charging.set(!m.charging.get());
			}), "stopping", () -> m.charging.get());
		var left = <div class="dash-glass flex flex-col gap-4 p-6" width={330} height={480}>
			<text class="dash-title">Battery</text>
			<canvas width={260} height={260} draw={ring()} />
			<div flexDirection={Row} justifyContent={Justify.SpaceBetween}>
				<div flexDirection={Column} gap={2}>
					<text class="text-xs ink-3">Range</text>
					<text class="text-sm font-semibold">${Math.round(m.distance(m.range.get())) + " " + m.distanceUnit()}</text>
				</div>
				<div flexDirection={Column} gap={2} alignItems={End}>
					<text class="text-xs ink-3">To the limit</text>
					<text class="text-sm font-semibold">${m.charging.get() && m.charge.get() < m.limit.get() ? Math.round(m.minutesToLimit.get()) + " min" : "–"}</text>
				</div>
			</div>
			{key}
		</div>;
		var middle = <div class="dash-glass flex flex-col gap-4 p-6" width={400} height={480}>
			<text class="dash-title">Charge limit</text>
			<div flexDirection={Column} gap={4}>
				{limit}
				<div flexDirection={Row} justifyContent={Justify.SpaceBetween}>
					<text class="text-xs ink-3">50%</text>
					<text class="text-sm font-semibold">${Math.round(m.limit.get()) + "%"}</text>
					<text class="text-xs ink-3">100%</text>
				</div>
			</div>
			<text class="text-sm font-medium">Charging curve</text>
			<canvas width={360} height={132} draw={curve()} />
			{toggleRow("Off-peak schedule", "Charge from 11:30 PM to 6:00 AM", scheduled)}
		</div>;
		var right = <div class="dash-glass flex flex-col gap-3 p-6" width={360} height={480}>
			<text class="dash-title">Stations near you</text>
			{station(0)}{station(1)}{station(2)}
		</div>;
		return <div position={Absolute} left={24} right={24} top={78} bottom={100} flexDirection={Row} justifyContent={Justify.Center} alignItems={Center} gap={16}>
			{left}{middle}{right}
		</div>;
	}
}
