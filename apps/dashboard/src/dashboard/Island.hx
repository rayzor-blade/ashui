package dashboard;

import ashui.animation.AnimatedValue;
import ashui.animation.AnimationScheduler;
import ashui.animation.SpringConfig;
import ashui.draw.DrawContext;
import ashui.draw.Stroke;
import ashui.icons.Remix;
import ashui.input.Events.PointerEvent;
import ashui.input.Pointer;
import ashui.layout.Element;
import ashui.reactive.Computed;
import ashui.reactive.Signal;
import ashui.types.Brush;
import ashui.types.Notch;
import ashui.types.Style;
import ashui.ui.Div;
import ashui.ui.Ref;
import dashboard.Widgets.*;

/** A number that springs to each target it is given, as a signal that layout reads. **/
private class Sprung {
	public final value:Signal<Float>;

	final spring:AnimatedValue;
	var ticker:Null<ashui.animation.AnimationScheduler.Ticker> = null;

	public function new(initial:Float, config:SpringConfig) {
		value = Signal.make(initial);
		spring = new AnimatedValue(AnimationScheduler.main, initial, config);
	}

	/** Springs toward `target` from where it is, mid-flight or not. **/
	public function to(target:Float):Void {
		// Already there and still: no spring to start.
		if (!spring.isAnimating() && Math.abs(value.get() - target) < 1e-6)
			return;
		spring.setTarget(target);
		// One ticker follows the spring; if the scheduler has dropped it, another is made.
		if (ticker != null && ticker.running)
			return;
		ticker = AnimationScheduler.main.addTicker(_ -> {
			value.set(spring.get());
			return spring.isAnimating();
		});
	}

	/** Jumps to `target`. **/
	public function snap(target:Float):Void {
		spring.setImmediate(target);
		value.set(target);
	}
}

/** One of the island's items: what it shows in the bar, and the panel it opens, `width` by `body` below the shoulders. **/
private typedef IslandItem = {id:String, width:Float, body:Float, bar:Element, panel:Void->Element};

/**
	The island: a black bar hanging from the top edge, its concave shoulders flaring into it, as a phone's island or a
	laptop's notch. It carries the greeting, the track playing, the weather, the network and the time.

	Hovering or tapping an item opens a black notched panel under it, its own concave shoulders meeting the bar's foot.
	The panel slides and resizes from item to item on springs, and folds away when the pointer leaves both the bar and the
	panel, or the open item is tapped again. The track's panel plays and pauses it, skips and seeks.

	The bar and the panel sit in a box of no size, so the island blocks nothing on the page but itself.
**/
class Island {
	/** How far the bar's shoulders flare into the top edge, and the panel's into the bar. **/
	static inline var SHOULDER = 18;

	static inline var PANEL_SHOULDER = 16;

	/** The bar's width and height below the edge. **/
	public static inline var BAR_WIDTH = 600;

	static inline var BAR = 50;

	/** The bar's and the panel's foot radii. **/
	static inline var FOOT = 24;

	static inline var PANEL_FOOT = 22;

	static inline var ACCENT = 0x7cc4ff;
	static inline var CYAN = 0x22d3ee;

	/** Bars rising and falling with the sound, as a player shows sound playing; still and low when nothing plays. **/
	static function equalizer(m:Model, music:Music):DrawContext->Void
		return ctx -> {
			var playing = music.playing();
			// Drawn again each frame only while there is sound to follow; still, it leaves the window at rest.
			if (playing)
				m.clock.get();
			var position = music.livePosition();
			for (i in 0...4) {
				var level = playing ? 0.12 + 0.88 * music.level(2 + i * 3, position) : 0.12;
				var h = 3 + 13 * level;
				ctx.fillRect(i * 5, 16 - h, 3, h, Brush.linear(0, 0, 0, 16).stop(0, ACCENT).stop(1, CYAN), 1.5);
			}
		};

	/** The track's progress, `w` wide. **/
	static function track(w:Float, music:Music):DrawContext->Void
		return ctx -> {
			var d = music.player.duration.get();
			var done = d > 0 ? Math.min(1, music.player.position.get() / d) : 0.0;
			ctx.fillRect(0, 4, w, 4, Brush.solid(0xffffff, 0.16), 2);
			if (done > 0)
				ctx.fillRect(0, 4, w * done, 4, Brush.linear(0, 0, w * done, 0).stop(0, CYAN).stop(1, ACCENT), 2);
			ctx.fillCircle(w * done, 6, 6, Brush.solid(0xffffff));
		};

	/** The island, centred across a page `width()` wide, which it follows if that changes. **/
	public static function build(width:Void->Float, m:Model, music:Music):Element {
		var active = Signal.make("");
		// What the panel shows: the open item's, kept while the panel folds away.
		var shown = Signal.make("");
		var centre = new Sprung(width() / 2, SpringConfig.gentle());
		var span = new Sprung(0, SpringConfig.snappy());
		var depth = new Sprung(0, SpringConfig.snappy());
		var bar = new Ref<Div>(), panel = new Ref<Div>();
		var barLeft = Computed.make(() -> (width() - BAR_WIDTH) / 2);

		function forecast(time:String, document:ashui.svg.Icon, temp:String):Element
			return <div flexDirection={Column} alignItems={Center} gap={5} flexGrow={1}>
				<text class="text-xs island-dim">${time}</text>
				{time == "Now" ? <div class="island-sun">{icon(document, "size-5")}</div> : <div class="island-dim">{icon(document, "size-5")}</div>}
				<text class="text-sm font-medium">${temp}</text>
			</div>;
		function heading(document:ashui.svg.Icon, title:Computed<String>, detail:Computed<String>):Element
			return <div flexDirection={Row} alignItems={Center} gap={12}>
				<div class="island-badge flex items-center justify-center" width={34} height={34}>{icon(document, "size-4")}</div>
				<div flexDirection={Column} gap={2}>
					<text class="text-sm font-semibold">${title.get()}</text>
					<text class="text-xs island-dim">${detail.get()}</text>
				</div>
			</div>;

		function cover(size:Float):Element {
			var hue = Computed.make(() -> Music.TRACKS[music.index.get()].hue);
			return <canvas width={size} height={size} draw={ctx -> Art.draw(size, hue.get())(ctx)} />;
		}

		function control(document:ashui.svg.Icon, act:Void->Void):Element
			return press(<div class="island-dim island-key">{icon(document, "size-5")}</div>, act);

		function playButton():Element {
			var b = <div class="island-play flex items-center justify-center" width={38} height={38}>
				<if {music.playing()}>{icon(Remix.PAUSE_FILL, "size-5")}</if>
				<if {!music.playing()}>{icon(Remix.PLAY_FILL, "size-5")}</if>
			</div>;
			return press(b, music.toggle);
		}

		/** A progress bar `w` wide that a press seeks. **/
		function scrub(w:Float):Element {
			var line = <div width={w} height={12}><canvas width={w} height={12} draw={track(w, music)} /></div>;
			ashui.input.Interaction.of(line.node).onClick(e -> {
				var b = line.tree.getBounds(line.node);
				if (b != null)
					music.seekFraction((e.x - b.x) / b.width);
			});
			return line;
		}

		var items:Array<IslandItem> = [
			{
				id: "drive",
				width: 300,
				body: 66,
				bar: <div flexDirection={Row} alignItems={Center} gap={8}>
					<div class="island-accent">{icon(Remix.CAR_LINE, "size-4")}</div>
					<text class="text-sm font-medium">${Model.greeting(m.minute.get())}</text>
				</div>,
				panel: () -> heading(Remix.CAR_LINE, Computed.make(() -> m.speed.get() > 1 ? "Driving" : "Ready to drive"),
					Computed.make(() -> Math.floor(m.charge.get()) + "% · " + Math.round(m.distance(m.range.get())) + " " + m.distanceUnit() + " range · doors "
						+ (m.locked.get() ? "locked" : "unlocked")))
			},
			{
				id: "music",
				width: 340,
				body: 168,
				bar: <div flexDirection={Row} alignItems={Center} gap={10}>
					{cover(22)}
					<canvas width={18} height={16} draw={equalizer(m, music)} />
				</div>,
				panel: () -> <div flexDirection={Column} gap={14} widthPercent={1}>
					<div flexDirection={Row} alignItems={Center} gap={12}>
						{cover(52)}
						<div flexDirection={Column} gap={2} flexGrow={1}>
							<text class="text-sm font-semibold">${live(() -> music.current().title)}</text>
							<text class="text-xs island-dim">${live(() -> music.current().artist + " · " + music.current().album)}</text>
						</div>
						<div class="island-accent">{icon(Remix.HEART_FILL, "size-4")}</div>
					</div>
					<div flexDirection={Column} gap={4}>
						{scrub(306)}
						<div flexDirection={Row} justifyContent={Justify.SpaceBetween}>
							<text class="text-xs island-dim">${Music.clockText(music.player.position.get())}</text>
							<text class="text-xs island-dim">${Music.clockText(music.player.duration.get())}</text>
						</div>
					</div>
					<div flexDirection={Row} justifyContent={Justify.Center} alignItems={Center} gap={30}>
						{control(Remix.SKIP_BACK_FILL, () -> music.advance(-1, music.playing()))}
						{playButton()}
						{control(Remix.SKIP_FORWARD_FILL, () -> music.advance(1, music.playing()))}
					</div>
				</div>
			},
			{
				id: "weather",
				width: 336,
				body: 150,
				bar: <div class="island-dim" flexDirection={Row} alignItems={Center} gap={6}>{icon(Remix.SUN_LINE, "size-4")}<text class="text-sm">21°</text></div>,
				panel: () -> <div flexDirection={Column} gap={14} widthPercent={1}>
					{heading(Remix.SUN_LINE, Computed.make(() -> "Sunny, 21°"), Computed.make(() -> "London · high 23°, low 14°"))}
					<div flexDirection={Row} widthPercent={1}>
						{forecast("Now", Remix.SUN_LINE, "21°")}{forecast("5 PM", Remix.SUN_LINE, "20°")}{forecast("6 PM", Remix.SUN_CLOUDY_LINE, "19°")}
						{forecast("7 PM", Remix.CLOUDY_LINE, "17°")}{forecast("8 PM", Remix.MOON_LINE, "15°")}
					</div>
				</div>
			},
			{
				id: "wifi",
				width: 272,
				body: 66,
				bar: <div class="island-dim">{icon(Remix.WIFI_LINE, "size-4")}</div>,
				panel: () -> heading(Remix.WIFI_LINE, Computed.make(() -> "Home-5G"), Computed.make(() -> "Connected · 640 Mbps"))
			},
			{
				id: "signal",
				width: 268,
				body: 66,
				bar: <div class="island-dim">{icon(Remix.SIGNAL_TOWER_LINE, "size-4")}</div>,
				panel: () -> heading(Remix.SIGNAL_TOWER_LINE, Computed.make(() -> "5G · strong"), Computed.make(() -> "Roaming off · 3.2 GB this month"))
			},
			{
				id: "time",
				width: 300,
				body: 66,
				bar: <text class="text-sm font-semibold">${Model.clockText(m.minute.get())}</text>,
				panel: () -> heading(Remix.CALENDAR_LINE, Computed.make(() -> DateTools.format(Date.now(), "%A, %e %B")),
					Computed.make(() -> m.charging.get() ? "Charging to " + Math.round(m.limit.get()) + "%" : "Not charging"))
			}
		];
		function find(id:String):Null<IslandItem> {
			for (item in items)
				if (item.id == id)
					return item;
			return null;
		}

		function open(item:IslandItem, under:ashui.layout.Node):Void {
			var at = under.tree.getBounds(under);
			if (at == null)
				return;
			// Centred under the item, kept to the bar's flat foot so the panel's shoulders meet it.
			var half = item.width / 2 + PANEL_SHOULDER;
			var left = barLeft.get();
			var lo = left + SHOULDER + FOOT + half, hi = left + BAR_WIDTH - SHOULDER - FOOT - half;
			var x = Math.max(lo, Math.min(hi, at.x + at.width / 2));
			if (active.get() == "") {
				// Opening afresh: it unfolds where it is wanted, narrow first, rather than sliding in from where it last was.
				centre.snap(x);
				span.snap(item.width * 0.3);
			} else
				centre.to(x);
			active.set(item.id);
			shown.set(item.id);
			span.to(item.width);
			depth.to(item.body);
		}
		function close():Void {
			if (active.get() == "")
				return;
			active.set("");
			depth.to(0);
			var item = find(shown.get());
			if (item != null)
				span.to(item.width * 0.3);
		}
		// Closes once the pointer is over neither the bar nor the panel.
		function leave(e:PointerEvent):Void {
			var tree = e.currentTarget.tree, at = Pointer.at(tree);
			for (ref in [bar, panel]) {
				var el = ref.get();
				var b = el == null ? null : tree.getBounds(el.node);
				if (b != null && at.x >= b.x && at.x <= b.x + b.width && at.y >= b.y && at.y <= b.y + b.height)
					return;
			}
			close();
		}

		function slot(item:IslandItem):Element
			return <div id={"island-" + item.id} class="island-item flex flex-row items-center" height={34} paddingLeft={10} paddingRight={10}
				bg={Computed.make(() -> active.get() == item.id ? Brush.solid(0xffffff, 0.12) : Brush.solid(0xffffff, 0))}
				onPointerEnter={e -> open(item, e.currentTarget)}
				onClick={e -> if (active.get() == item.id) close() else open(item, e.currentTarget)}>
				{item.bar}
			</div>;

		var openness = Computed.make(() -> Math.max(0, Math.min(1, (depth.value.get() - 20) / 40)));
		return <div position={Absolute} left={0} top={0} width={0} height={0}>
			<!-- The concave shoulders inset the bar's top: the box is raised by that inset, so the flare meets the top edge. -->
			<div ref={bar} notch={Notch.concaveTop(SHOULDER, FOOT)} class="dash-island flex flex-row items-center justify-between"
				position={Absolute} left={barLeft} top={-SHOULDER} width={BAR_WIDTH} height={SHOULDER + BAR}
				paddingTop={SHOULDER} paddingLeft={SHOULDER + 10} paddingRight={SHOULDER + 10} onPointerLeave={leave}>
				{slot(items[0])}
				<div class="island-sep" width={1} height={18} />
				{slot(items[1])}{slot(items[2])}{slot(items[3])}{slot(items[4])}{slot(items[5])}
			</div>
			<if {depth.value.get() > 0.5}>
				<!-- The panel's shoulders meet the bar's foot: its box starts that inset above it. -->
				<div ref={panel} notch={Notch.concaveTop(PANEL_SHOULDER, PANEL_FOOT)} class="dash-island flex flex-col overflow-hidden"
					position={Absolute} top={BAR - PANEL_SHOULDER}
					left={Computed.make(() -> centre.value.get() - span.value.get() / 2 - PANEL_SHOULDER)}
					width={Computed.make(() -> span.value.get() + PANEL_SHOULDER * 2)}
					height={Computed.make(() -> PANEL_SHOULDER + depth.value.get())}
					paddingTop={PANEL_SHOULDER + 14} paddingLeft={PANEL_SHOULDER + 18} paddingRight={PANEL_SHOULDER + 18}
					onPointerLeave={leave}>
					<div opacity={openness} flexShrink={0} widthPercent={1}>
						<for {id in [shown.get()]}>
							{find(id) == null ? <div /> : find(id).panel()}
						</for>
					</div>
				</div>
			</if>
		</div>;
	}
}
