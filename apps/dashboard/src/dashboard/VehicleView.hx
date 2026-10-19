package dashboard;

import ashui.components.ToggleSwitch;
import ashui.draw.DrawContext;
import ashui.draw.Path;
import ashui.draw.Stroke;
import ashui.icons.Remix;
import ashui.layout.Element;
import ashui.math.Mat4;
import ashui.math.Vec3;
import ashui.reactive.Computed;
import ashui.types.Brush;
import ashui.types.Style;
import ashui.ui.Ref;
import dashboard.Ink.*;
import dashboard.Tab.Gear;
import dashboard.Widgets.*;

private typedef Callout = {at:Vec3, facing:Vec3, lean:Vec3, label:String, note:Void->String, icon:ashui.svg.Icon};

/**
	The page the car opens on: the car in the middle, turned by the pointer, with panels round it, the speed and gear, the
	charge, the tyres, the climate, the week's consumption and the chargers near, each of which does what it shows. Three
	callouts on the car follow points on its body as it turns, and the doors' one locks and unlocks it.
**/
class VehicleView {
	/** How far the side columns reach in from the edges, which the callouts keep clear of. **/
	static inline var LEFT_PANEL = 340;

	static inline var RIGHT_PANEL = 364;

	final m:Model;
	final stage:Stage;
	final screen:Screen;
	final map:StreetMap;
	final canvas = new Ref<ashui.ui.Canvas>();
	final callouts:Array<Callout>;
	final placed:Computed<Array<{x:Float, y:Float, cx:Float, cy:Float, opacity:Float}>>;

	static inline var CHIP_WIDTH = 204.0;
	static inline var CHIP_HEIGHT = 40.0;

	public function new(m:Model, stage:Stage, screen:Screen, map:StreetMap) {
		this.m = m;
		this.stage = stage;
		this.screen = screen;
		this.map = map;
		callouts = [
			{at: new Vec3(0.9, 0.7, -0.2), facing: new Vec3(1, 0, 0), lean: new Vec3(0, 1, 0), label: "Doors", note: () -> m.locked.get() ? "Locked" : "Unlocked",
				icon: Remix.LOCK_LINE},
			{at: new Vec3(0.86, 0.92, 1.6), facing: new Vec3(1, 0, 0.25), lean: new Vec3(0, -0.8, 0), label: "Charge port", note: () -> m.charging.get() ? "Charging" : "Idle",
				icon: Remix.FLASHLIGHT_LINE},
			{at: new Vec3(0.0, 1.45, 0.25), facing: new Vec3(0, 1, 0), lean: new Vec3(0.3, -1.5, 0), label: "Cabin", note: () -> Std.string(m.target.get()) + "°",
				icon: Remix.TEMP_HOT_LINE}
		];
		placed = Computed.make(layoutCallouts);
	}

	function viewWidth():Float {
		var c = canvas.get();
		var w = c == null ? 0.0 : c.laidWidth();
		return w > 0 ? w : screen.width.get();
	}

	function viewHeight():Float {
		var c = canvas.get();
		var h = c == null ? 0.0 : c.laidHeight();
		return h > 0 ? h : screen.height.get();
	}

	/** Where a point of the scene lands in the page, in layout units. **/
	function project(p:Vec3, width:Float, height:Float):{x:Float, y:Float} {
		var cam = stage.camera.camera();
		var mat = cam.projection(width / height).mul(cam.view());
		var cx = mat.get(0, 0) * p.x + mat.get(1, 0) * p.y + mat.get(2, 0) * p.z + mat.get(3, 0);
		var cy = mat.get(0, 1) * p.x + mat.get(1, 1) * p.y + mat.get(2, 1) * p.z + mat.get(3, 1);
		var cw = mat.get(0, 3) * p.x + mat.get(1, 3) * p.y + mat.get(2, 3) * p.z + mat.get(3, 3);
		return {x: (cx / cw * 0.5 + 0.5) * width, y: (0.5 - cy / cw * 0.5) * height};
	}

	/** Each chip sits on an ellipse round the car, out from its point, so the chips circle the car as it is turned; they keep clear of the side panels and the dock. **/
	function layoutCallouts():Array<{x:Float, y:Float, cx:Float, cy:Float, opacity:Float}> {
		var width = viewWidth(), height = viewHeight();
		var left = LEFT_PANEL, right = RIGHT_PANEL;
		var away = Stage.DISTANCE / stage.camera.distance.get();
		var eye = stage.camera.eye(), middle = project(new Vec3(0, 0.65, 0), width, height);
		var scale = Math.max(0.55, Math.min(1.4, Math.min(width / 1600, height / 820) * 1.3));
		var chips = [
			for (c in callouts) {
				var p = c.at;
				var n = c.facing.normalize();
				var seen = n.dot(eye.sub(p).normalize());
				var at = project(p, width, height);
				var dx = (at.x - middle.x) / 300 + c.lean.x, dy = (at.y - middle.y) / 170 + c.lean.y;
				var len = Math.max(1e-6, Math.sqrt(dx * dx + dy * dy));
				var cx = Math.max(left + 16 + CHIP_WIDTH / 2, Math.min(width - right - 16 - CHIP_WIDTH / 2, middle.x + dx / len * 400 * scale * away));
				var cy = Math.max(72 + CHIP_HEIGHT / 2, Math.min(height - 200 - CHIP_HEIGHT / 2, middle.y + dy / len * 235 * scale * away));
				{x: at.x, y: at.y, cx: cx, cy: cy, opacity: Math.max(0, Math.min(1, (seen - 0.12) / 0.25))};
			}
		];
		// Chips that would overlap are pushed apart sideways, each half the overlap, then kept clear of the panels again.
		for (_ in 0...3)
			for (i in 0...chips.length)
				for (j in i + 1...chips.length) {
					var a = chips[i], b = chips[j];
					if (a.opacity < 0.05 || b.opacity < 0.05 || Math.abs(a.cy - b.cy) >= CHIP_HEIGHT + 8)
						continue;
					var gap = b.cx - a.cx, need = CHIP_WIDTH + 12 - Math.abs(gap);
					if (need <= 0)
						continue;
					var way = gap != 0 ? (gap > 0 ? 1.0 : -1.0) : (b.x >= a.x ? 1.0 : -1.0);
					a.cx -= way * need / 2;
					b.cx += way * need / 2;
				}
		for (c in chips)
			c.cx = Math.max(left + 16 + CHIP_WIDTH / 2, Math.min(width - right - 16 - CHIP_WIDTH / 2, c.cx));
		return chips;
	}

	function leaders(ctx:DrawContext):Void {
		follow();
		var primary = primary();
		for (a in placed.get()) {
			if (a.opacity <= 0)
				continue;
			ctx.pushOpacity(a.opacity);
			var line = new Path().moveTo(a.x, a.y);
			if (Math.abs(a.cx - a.x) < CHIP_WIDTH / 2 - 16)
				line.lineTo(a.x, a.cy + (a.cy > a.y ? -CHIP_HEIGHT / 2 : CHIP_HEIGHT / 2));
			else {
				var end = a.cx + (a.cx > a.x ? -CHIP_WIDTH / 2 : CHIP_WIDTH / 2);
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
		var chip = <div class="dash-chip flex flex-row items-center gap-2 pl-2 pr-3" position={Absolute}
			left={Computed.make(() -> placed.get()[i].cx - CHIP_WIDTH / 2)} top={Computed.make(() -> placed.get()[i].cy - CHIP_HEIGHT / 2)}
			opacity={Computed.make(() -> placed.get()[i].opacity)} width={CHIP_WIDTH} height={CHIP_HEIGHT}
			pointerEvents={i == 0 ? PointerEvents.Auto : PointerEvents.None}>
			<div class="dash-chip-icon flex items-center justify-center" width={26} height={26}>{icon(c.icon, "size-3.5")}</div>
			<text class="text-xs font-medium" flexGrow={1}>${c.label}</text>
			<text class="text-xs ink-2">${live(() -> c.note())}</text>
		</div>;
		// Only the doors' chip takes presses; the others are a label on the car.
		return i == 0 ? press(chip, () -> m.locked.set(!m.locked.get())) : chip;
	}

	// --- panels ---

	function header(title:String, right:Element):Element
		return <div class="dash-header flex flex-row items-center justify-between pl-4 pr-4" height={44}>
			<text>${title}</text>
			{right}
		</div>;

	function stat(label:String, value:Computed<String>, unit:Computed<String>):Element
		return <div flexDirection={Column} gap={2} flexGrow={1} flexBasis={0} alignItems={Center}>
			<text class="text-xs ink-3">${label}</text>
			<div flexDirection={Row} alignItems={End} gap={3}>
				<text class="text-sm font-semibold">${value.get()}</text>
				<text class="text-xs ink-2">${unit.get()}</text>
			</div>
		</div>;

	function gear(g:Gear, letter:String):Element
		return flag(press(<div class="dash-gear flex items-center justify-center" width={22} height={22}><text>${letter}</text></div>, () -> m.shift(g)), "on",
			() -> m.gear.get() == g);

	function round(document:ashui.svg.Icon, label:Computed<String>, on:Void->Bool, toggle:Void->Void):Element {
		var button = flag(press(<div class="dash-round flex items-center justify-center" width={46} height={46}>{icon(document, "size-5")}</div>, toggle), "on", on);
		return <div flexDirection={Column} alignItems={Center} gap={6}>
			{button}
			<text class="text-xs ink-3">${label.get()}</text>
		</div>;
	}

	function charger(i:Int):Element {
		var c = Model.CHARGERS[i];
		var level = c.free == 0 ? 2 : c.free < 3 ? 1 : 0;
		var free = c.free == 0 ? "Full" : c.free + " free";
		var state = level == 0 ? <text class="text-xs font-semibold good">${free}</text>
			: level == 1 ? <text class="text-xs font-semibold warn">${free}</text> : <text class="text-xs font-semibold ink-3">${free}</text>;
		var row = <div class="dash-row flex flex-row items-center gap-3 px-2" height={40}>
			<div class="dash-chip-icon flex items-center justify-center" width={32} height={32}>{icon(Remix.CHARGING_PILE_2_LINE, "size-4")}</div>
			<div flexDirection={Column} gap={1} flexGrow={1}>
				<text class="text-sm font-medium">${c.name}</text>
				<text class="text-xs ink-3">${live(() -> Std.string(Math.round(m.distance(c.km) * 10) / 10) + " " + m.distanceUnit() + " · " + c.kw + " kW")}</text>
			</div>
			{state}
		</div>;
		return flag(press(row, () -> {
			m.destination.set(i);
			m.guiding.set(true);
			m.tab.set(Navigate);
		}), "on", () -> m.destination.get() == i);
	}

	function drivePanel():Element
		return <div class="dash-glass flex flex-col">
			{header("Drive", <div flexDirection={Row} gap={2}>{gear(P, "P")}{gear(R, "R")}{gear(N, "N")}{gear(D, "D")}</div>)}
			<div class="flex flex-col items-center px-4 pb-4 gap-3">
				<canvas width={284} height={210} draw={Gauges.speedometer(m)} />
				<div flexDirection={Row} alignItems={Center} widthPercent={1}>
					{stat("Trip", Computed.make(() -> Std.string(Math.round(m.distance(m.trip.get()) * 10) / 10)), Computed.make(() -> m.distanceUnit()))}
					<div class="dash-sep" width={1} height={28} />
					{stat("Average", Computed.make(() -> Std.string(Math.round(m.shown(62)))), Computed.make(() -> m.unit()))}
					<div class="dash-sep" width={1} height={28} />
					{stat("Odometer", Computed.make(() -> thousands(Math.round(m.distance(m.odometer.get())))), Computed.make(() -> m.distanceUnit()))}
				</div>
			</div>
		</div>;

	static function thousands(n:Int):String {
		var s = Std.string(n), out = "";
		for (i in 0...s.length)
			out += (i > 0 && (s.length - i) % 3 == 0 ? " " : "") + s.charAt(i);
		return out;
	}

	function batteryPanel():Element {
		var chip = flag(press(<div class="charge flex flex-row items-center gap-1">{icon(Remix.FLASHLIGHT_FILL, "size-3")}
			<text class="text-xs font-semibold">${m.charging.get() ? "Charging · 11 kW" : "Plugged in"}</text></div>, () -> m.charging.set(!m.charging.get())), "on",
			() -> m.charging.get());
		return <div class="dash-glass flex flex-col">
			{header("Battery", chip)}
			<div class="flex flex-col px-4 pb-4 gap-3">
				<div flexDirection={Row} alignItems={End} justifyContent={Justify.SpaceBetween}>
					<div flexDirection={Row} alignItems={End} gap={2}>
						<text class="text-3xl font-semibold">${Std.string(Math.floor(m.charge.get()))}</text>
						<text class="text-base ink-2" paddingBottom={3}>%</text>
					</div>
					<text class="text-sm ink-2" paddingBottom={3}>${Std.string(Math.round(m.distance(m.range.get()))) + " " + m.distanceUnit() + " range"}</text>
				</div>
				<canvas width={284} height={30} draw={Gauges.battery(m)} />
				<div flexDirection={Row} justifyContent={Justify.SpaceBetween}>
					<text class="text-xs ink-3">${live(() -> untilFull())}</text>
					<text class="text-xs ink-3">${"Limit " + Math.round(m.limit.get()) + "%"}</text>
				</div>
			</div>
		</div>;
	}

	function untilFull():String {
		var minutes = Math.round(m.minutesToLimit.get());
		if (!m.charging.get())
			return "Not charging";
		return minutes <= 0 ? "At the limit" : (minutes >= 60 ? Std.int(minutes / 60) + " h " : "") + (minutes % 60) + " min to the limit";
	}

	function tyresPanel():Element
		return <div class="dash-glass flex flex-col">
			{header("Tyres", <text class="text-xs ink-2">Pressure · temperature</text>)}
			<div class="flex flex-col px-4 pb-4">
				<canvas width={284} height={150} draw={Gauges.tyres(m)} />
			</div>
		</div>;

	function nudge(label:String, by:Float):Element
		return press(<div class="dash-nudge flex items-center justify-center" width={30} height={30}><text>${label}</text></div>, () -> m.setTemperature(m.target.get() + by));

	function climatePanel():Element {
		var auto = <toggle-switch checked={m.auto} />;
		return <div class="dash-glass flex flex-col">
			{header("Climate", <div flexDirection={Row} alignItems={Center} gap={8}><text class="text-xs">Auto</text>{auto}</div>)}
			<div class="flex flex-col items-center px-4 pb-4 gap-3">
				<div width={308} height={130}>
					<canvas width={308} height={130} draw={Gauges.climate(m)} />
					<div position={Absolute} left={30} top={54}>{nudge("−", -0.5)}</div>
					<div position={Absolute} right={30} top={54}>{nudge("+", 0.5)}</div>
				</div>
				<div flexDirection={Row} justifyContent={Justify.SpaceBetween} widthPercent={1}>
					{round(Remix.SNOWFLAKE_LINE, Computed.make(() -> "A/C"), () -> m.ac.get(), () -> m.ac.set(!m.ac.get()))}
					{round(Remix.WINDY_LINE, Computed.make(() -> "Fan " + m.fan.get()), () -> m.fan.get() > 0, () -> m.fan.set((m.fan.get() + 1) % 6))}
					{round(Remix.SUN_LINE, Computed.make(() -> "Defrost"), () -> m.defrost.get(), () -> m.defrost.set(!m.defrost.get()))}
					{round(Remix.SHIELD_CHECK_LINE, Computed.make(() -> "Guard"), () -> m.guard.get(), () -> m.guard.set(!m.guard.get()))}
				</div>
			</div>
		</div>;
	}

	function energyPanel():Element
		return <div class="dash-glass flex flex-col">
			{header("Energy", <text class="text-xs ink-2">${live(() -> "kWh / 100 " + m.distanceUnit())}</text>)}
			<div class="flex flex-col px-4 pb-4 gap-1">
				<canvas width={308} height={100} draw={Gauges.energy(m)} />
				<div flexDirection={Row} justifyContent={Justify.SpaceBetween}>
					<text class="text-xs ink-3">This week</text>
					<text class="text-xs good">6% under last week</text>
				</div>
			</div>
		</div>;

	function chargersPanel():Element {
		var small = <canvas width={316} height={100} draw={ctx -> {
			follow();
			map.draw(ctx, 316, 100, 12, light(), primary(), [GREEN, AMBER, muted()], 0.0, 0, 1.0, true, false);
		}} />;
		return <div class="dash-glass flex flex-col">
			{header("Nearby chargers", <text class="text-xs ink-2">On route</text>)}
			<div class="flex flex-col px-3 pb-3 gap-1">
				<div width={316} height={100} marginBottom={4}>
					{small}
					<div class="map-inset" position={Absolute} left={0} top={0} width={316} height={100} />
					<text class="map-credit" position={Absolute} right={6} bottom={4}>© OpenStreetMap</text>
				</div>
				{charger(0)}{charger(1)}
			</div>
		</div>;
	}

	function swatch(i:Int):Element {
		var p = Paint.ALL[i];
		var dot = <div class="dash-swatch" width={22} height={22} bg={Brush.solid(p.color)} />;
		return flag(press(dot, () -> m.paint.set(i)), "on", () -> m.paint.get() == i);
	}

	function paintPill():Element
		return <div class="dash-chip flex flex-row items-center gap-3 px-3" height={40}>
			<text class="text-xs ink-2">${Paint.ALL[m.paint.get()].name}</text>
			{swatch(0)}{swatch(1)}{swatch(2)}{swatch(3)}{swatch(4)}{swatch(5)}
		</div>;

	public function build():Element {
		// The page has no size of its own, so the car's scene takes the pointer, to orbit, wherever a panel is not over it.
		var right = Computed.make(() -> screen.width.get() - 24 - 340.0);
		var barTop = Computed.make(() -> screen.height.get() - 108 - 40.0);
		var page = <div position={Absolute} left={0} top={0} width={0} height={0}>
			<canvas ref={canvas} width={screen.width} height={screen.height} draw={leaders} position={Absolute} left={0} top={0} pointerEvents={PointerEvents.None} />
			{callout(0)}{callout(1)}{callout(2)}
			<div flexDirection={Column} gap={16} position={Absolute} left={24} top={24} width={316}>
				{drivePanel()}{batteryPanel()}{tyresPanel()}
			</div>
			<div flexDirection={Column} gap={12} position={Absolute} left={right} top={24} width={340}>
				{climatePanel()}{energyPanel()}{chargersPanel()}
			</div>
			<div position={Absolute} left={0} top={barTop} width={screen.width} height={40} flexDirection={Row} justifyContent={Justify.Center} alignItems={Center}>
				{paintPill()}
			</div>
		</div>;
		return page;
	}
}
