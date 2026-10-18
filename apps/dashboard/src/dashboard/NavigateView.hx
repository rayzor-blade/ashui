package dashboard;

import ashui.draw.DrawContext;
import ashui.icons.Remix;
import ashui.layout.Element;
import ashui.reactive.Computed;
import ashui.types.Style;
import dashboard.Ink.*;
import dashboard.Widgets.*;

/**
	The Navigate page: the street map as large as the page gives it, the chargers to drive to, and the guidance for the one
	chosen: how far and how long, the next turn, and the car on its way. The map's buttons zoom it, and searching narrows the
	list.
**/
class NavigateView {
	static final TURNS = [
		{what: "Turn left onto Goods Way", at: 0.0},
		{what: "Continue past the canal", at: 0.35},
		{what: "Turn right onto Stable Street", at: 0.7},
		{what: "Your charger is on the right", at: 0.9}
	];

	final m:Model;
	final map:StreetMap;
	final screen:Screen;

	public function new(m:Model, map:StreetMap, screen:Screen) {
		this.m = m;
		this.map = map;
		this.screen = screen;
	}

	function view():DrawContext->Void
		return ctx -> {
			follow();
			var free = [GREEN, AMBER, muted()];
			map.draw(ctx, ctx.width, ctx.height, 36, light(), primary(), free, m.guiding.get() ? (m.clock.get() * 32) % 16 : 0, m.destination.get(), m.zoom.get(),
				m.guiding.get());
		};

	function zoomKey(document:ashui.svg.Icon, by:Float):Element
		return press(<div class="dash-chip flex items-center justify-center" width={44} height={44}>{icon(document, "size-5")}</div>,
			() -> m.zoom.set(Math.max(0.6, Math.min(3, m.zoom.get() * by))));

	function turn():String {
		var gone = 1 - m.remaining() / Math.max(0.001, Model.CHARGERS[m.destination.get()].km);
		var what = TURNS[0].what;
		for (t in TURNS)
			if (gone >= t.at)
				what = t.what;
		return what;
	}

	function destination(i:Int):Element {
		var c = Model.CHARGERS[i];
		var level = c.free == 0 ? 2 : c.free < 3 ? 1 : 0;
		var free = c.free == 0 ? "Full" : c.free + " of " + c.of + " free";
		var state = level == 0 ? <text class="text-xs font-semibold good">${free}</text>
			: level == 1 ? <text class="text-xs font-semibold warn">${free}</text> : <text class="text-xs font-semibold ink-3">${free}</text>;
		var row = <div class="dash-tile flex flex-row items-center gap-3 px-3" height={60}>
			<div class="dash-chip-icon flex items-center justify-center" width={36} height={36}>{icon(Remix.CHARGING_PILE_2_LINE, "size-5")}</div>
			<div flexDirection={Column} gap={2} flexGrow={1}>
				<text class="text-sm font-semibold">${c.name}</text>
				<text class="text-xs ink-3">${live(() -> Std.string(Math.round(m.distance(c.km) * 10) / 10) + " " + m.distanceUnit() + " · " + c.kw + " kW")}</text>
			</div>
			{state}
		</div>;
		return flag(press(row, () -> m.navigateTo(i)), "on", () -> m.destination.get() == i && m.guiding.get());
	}

	function matches(i:Int):Bool {
		var q = m.search.get().toLowerCase();
		return q == "" || Model.CHARGERS[i].name.toLowerCase().indexOf(q) >= 0;
	}

	function guidance():Element {
		var eta = Computed.make(() -> Math.max(1, Math.round(m.minutesAway())));
		function go()
			return press(<div class="dash-go flex flex-row items-center justify-center gap-2" height={44}>{icon(Remix.NAVIGATION_FILL, "size-4")}<text class="text-sm font-semibold">Start</text></div>,
			() -> m.navigateTo(m.destination.get()));
		function stop()
			return press(<div class="dash-danger flex flex-row items-center justify-center gap-2" height={44}>{icon(Remix.CLOSE_CIRCLE_LINE, "size-4")}<text class="text-sm font-semibold">End</text></div>,
			() -> m.guiding.set(false));
		return <div class="flex flex-col gap-3">
			<if {m.guiding.get()}>
				<div class="flex flex-col gap-2">
					<div flexDirection={Row} alignItems={End} gap={6}>
						<text class="dash-big">${eta.get() + " min"}</text>
						<text class="text-sm ink-2" paddingBottom={4}>${live(() -> Std.string(Math.round(m.distance(m.remaining()) * 10) / 10) + " " + m.distanceUnit())}</text>
					</div>
					<div class="dash-tile flex flex-row items-center gap-3 px-3" height={52}>
						<div class="accent">{icon(Remix.ARROW_UP_LINE, "size-5")}</div>
						<text class="text-sm font-medium">${live(() -> turn())}</text>
					</div>
				</div>
			</if>
			<if {!m.guiding.get()}>
				<div class="flex flex-col gap-1">
					<text class="text-sm font-semibold">${live(() -> m.remaining() <= 0 ? "You have arrived" : "Ready")}</text>
					<text class="text-xs ink-3">Pick a charger, then start</text>
				</div>
			</if>
			<if {m.guiding.get()}>{stop()}</if>
			<if {!m.guiding.get()}>{go()}</if>
		</div>;
	}

	public function build():Element {
		function side()
			return <div class="dash-glass flex flex-col gap-4 p-4" width={360}>
			<text class="dash-title">Drive to</text>
			<input value={m.search} placeholder="Search chargers" widthPercent={1} />
			<div class="flex flex-col gap-2">
				<for {i in [for (k in 0...Model.CHARGERS.length) if (matches(k)) k]}>{destination(i)}</for>
			</div>
			<div flexGrow={1} />
			{guidance()}
		</div>;
		var mapCard = <div class="dash-glass" flexGrow={1} flexBasis={0} heightPercent={1}>
			<canvas widthPercent={1} heightPercent={1} draw={view()} />
			<div position={Absolute} right={16} bottom={16} flexDirection={Column} gap={8}>{zoomKey(Remix.ADD_LINE, 1.35)}{zoomKey(Remix.SUBTRACT_LINE, 1 / 1.35)}</div>
		</div>;
		return <div position={Absolute} left={24} right={24} top={78} bottom={100} flexDirection={Row} gap={16}>
			{mapCard}
			<if {screen.width.get() >= 820}>{side()}</if>
		</div>;
	}
}
