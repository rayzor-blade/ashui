import DashIcons.*;
import ashui.animation.AnimatedValue;
import ashui.animation.AnimationScheduler;
import ashui.animation.SpringConfig;
import ashui.draw.DrawContext;
import ashui.draw.Stroke;
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

/** A number that springs to each target it is given, as a signal that layout reads. **/
private class Sprung {
	public final value:Signal<Float>;

	final spring:AnimatedValue;
	var ticking = false;

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
		if (ticking)
			return;
		ticking = true;
		AnimationScheduler.main.addTicker(_ -> {
			value.set(spring.get());
			if (spring.isAnimating())
				return true;
			ticking = false;
			return false;
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
	The banner's island: a black bar hanging from the top edge, its concave
	shoulders flaring into it, as a phone's island or a laptop's notch. It
	carries the greeting, the track playing, the weather, the network and
	the time.

	Hovering or tapping an item opens a black notched panel under it, its own
	concave shoulders meeting the bar's foot, as Blinc's notch demo's
	menu-bar dropdown does. The panel slides and resizes from item to item
	on springs, and folds away when the pointer leaves both the bar and the
	panel, or the open item is tapped again.

	The bar and the panel sit in a box of no size, so the island blocks
	nothing on the page but itself.
**/
class Island {
	/** How far the bar's shoulders flare into the top edge, and the panel's into the bar. **/
	static inline var SHOULDER = 18;
	static inline var PANEL_SHOULDER = 16;

	/** The bar's width and height below the edge. **/
	static inline var BAR_WIDTH = 600;
	static inline var BAR = 50;

	/** The bar's and the panel's foot radii. **/
	static inline var FOOT = 24;
	static inline var PANEL_FOOT = 22;

	static inline var ACCENT = 0x7cc4ff;
	static inline var CYAN = 0x22d3ee;

	static function icon(markup:String, classes:String):Element {
		var svg = new ashui.ui.Svg(ashui.svg.Icon.fromMarkup(markup));
		ashui.css.Identity.of(svg.tree, svg.node.id).addClasses(classes.split(" "));
		return svg;
	}

	/** Album art `size` square: a sunset gradient with rings round a disc, as a vinyl's label. **/
	static function cover(size:Float):DrawContext->Void
		return ctx -> {
			var k = size / 56;
			ctx.pushClipRect(0, 0, size, size, 12 * k);
			ctx.fillRect(0, 0, size, size, Brush.linear(0, 0, size, size).stop(0, 0x7c3aed).stop(0.55, 0xdb2777).stop(1, 0xf59e0b));
			for (i in 0...4)
				ctx.strokeCircle(42 * k, 44 * k, (10 + i * 9) * k, new Stroke(1.2 * k), Brush.solid(0xffffff, 0.35 - i * 0.07));
			ctx.fillCircle(42 * k, 44 * k, 6 * k, Brush.solid(0xffffff, 0.85));
			ctx.popClip();
		};

	/** Four bars rising and falling out of step with `clock`, as a player shows sound playing; each beats a whole number of times in 12 s, so it loops. **/
	static function equalizer(clock:Signal<Float>):DrawContext->Void
		return ctx -> {
			var t = clock.get();
			for (i in 0...4) {
				var level = 0.3 + 0.7 * Math.abs(Math.sin(Math.PI * 2 * t * [19, 23, 26, 30][i] / 12 + i * 1.9));
				var h = 3 + 13 * level;
				ctx.fillRect(i * 5, 16 - h, 3, h, Brush.linear(0, 0, 0, 16).stop(0, ACCENT).stop(1, CYAN), 1.5);
			}
		};

	/** The track's progress, `w` wide. **/
	static function track(w:Float):DrawContext->Void
		return ctx -> {
			var done = 0.42;
			ctx.fillRect(0, 4, w, 4, Brush.solid(0xffffff, 0.16), 2);
			ctx.fillRect(0, 4, w * done, 4, Brush.linear(0, 0, w * done, 0).stop(0, CYAN).stop(1, ACCENT), 2);
			ctx.fillCircle(w * done, 6, 6, Brush.solid(0xffffff));
		};

	/** The island, centred across a page `width` wide, its equalizer moving with `clock`, in seconds. **/
	public static function build(width:Float, clock:Signal<Float>):Element {
		var active = Signal.make("");
		// What the panel shows: the open item's, kept while the panel folds away.
		var shown = Signal.make("");
		var centre = new Sprung(width / 2, SpringConfig.gentle());
		var span = new Sprung(0, SpringConfig.snappy());
		var depth = new Sprung(0, SpringConfig.snappy());
		var bar = new Ref<Div>(), panel = new Ref<Div>();
		var barLeft = (width - BAR_WIDTH) / 2;

		function forecast(time:String, markup:String, temp:String):Element
			return <div flexDirection={Column} alignItems={Center} gap={5} flexGrow={1}>
				<text class="text-xs island-dim">${time}</text>
				{time == "Now" ? <div class="island-sun">{icon(markup, "size-5")}</div> : <div class="island-dim">{icon(markup, "size-5")}</div>}
				<text class="text-sm font-medium">${temp}</text>
			</div>;
		function heading(markup:String, title:String, detail:String):Element
			return <div flexDirection={Row} alignItems={Center} gap={12}>
				<div class="island-badge flex items-center justify-center" width={34} height={34}>{icon(markup, "size-4")}</div>
				<div flexDirection={Column} gap={2}>
					<text class="text-sm font-semibold">${title}</text>
					<text class="text-xs island-dim">${detail}</text>
				</div>
			</div>;

		var items:Array<IslandItem> = [
			{
				id: "drive",
				width: 300,
				body: 66,
				bar: <div flexDirection={Row} alignItems={Center} gap={8}>
					<div class="island-accent">{icon(ROADSTER, "size-4")}</div>
					<text class="text-sm font-medium">Good afternoon</text>
				</div>,
				panel: () -> heading(ROADSTER, "Ready to drive", "72% · 412 km range · doors locked")
			},
			{
				id: "music",
				width: 340,
				body: 168,
				bar: <div flexDirection={Row} alignItems={Center} gap={10}>
					<canvas width={22} height={22} draw={cover(22)} />
					<canvas width={18} height={16} draw={equalizer(clock)} />
				</div>,
				panel: () -> <div flexDirection={Column} gap={14} widthPercent={1}>
					<div flexDirection={Row} alignItems={Center} gap={12}>
						<canvas width={52} height={52} draw={cover(52)} />
						<div flexDirection={Column} gap={2} flexGrow={1}>
							<text class="text-sm font-semibold">Night Drive</text>
							<text class="text-xs island-dim">Aurora Lane · Coastline</text>
						</div>
						<div class="island-accent">{icon(HEART, "size-4")}</div>
					</div>
					<div flexDirection={Column} gap={4}>
						<canvas width={306} height={12} draw={track(306)} />
						<div flexDirection={Row} justifyContent={Justify.SpaceBetween}>
							<text class="text-xs island-dim">1:42</text>
							<text class="text-xs island-dim">4:03</text>
						</div>
					</div>
					<div flexDirection={Row} justifyContent={Justify.Center} alignItems={Center} gap={30}>
						<div class="island-dim">{icon(SKIP_BACK, "size-5")}</div>
						<div class="island-play flex items-center justify-center" width={38} height={38}>{icon(PAUSE, "size-5")}</div>
						<div class="island-dim">{icon(SKIP_FORWARD, "size-5")}</div>
					</div>
				</div>
			},
			{
				id: "weather",
				width: 336,
				body: 150,
				bar: <div class="island-dim" flexDirection={Row} alignItems={Center} gap={6}>{icon(SUN, "size-4")}<text class="text-sm">21°</text></div>,
				panel: () -> <div flexDirection={Column} gap={14} widthPercent={1}>
					{heading(SUN, "Sunny, 21°", "London · high 23°, low 14°")}
					<div flexDirection={Row} widthPercent={1}>
						{forecast("Now", SUN, "21°")}{forecast("5 PM", SUN, "20°")}{forecast("6 PM", SUN_CLOUD, "19°")}
						{forecast("7 PM", CLOUD, "17°")}{forecast("8 PM", MOON, "15°")}
					</div>
				</div>
			},
			{
				id: "wifi",
				width: 272,
				body: 66,
				bar: <div class="island-dim">{icon(WIFI, "size-4")}</div>,
				panel: () -> heading(WIFI, "Home-5G", "Connected · 640 Mbps")
			},
			{
				id: "signal",
				width: 268,
				body: 66,
				bar: <div class="island-dim">{icon(SIGNAL, "size-4")}</div>,
				panel: () -> heading(SIGNAL, "5G · strong", "Roaming off · 3.2 GB this month")
			},
			{
				id: "time",
				width: 300,
				body: 66,
				bar: <text class="text-sm font-semibold">4:12 PM</text>,
				panel: () -> heading(CALENDAR, "Friday, 16 October", "Charge to 80% at 5:30 PM")
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
			var lo = barLeft + SHOULDER + FOOT + half, hi = barLeft + BAR_WIDTH - SHOULDER - FOOT - half;
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
