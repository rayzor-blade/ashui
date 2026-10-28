package ashui.components;

import ashui.animation.AnimationScheduler;
import ashui.css.Css;
import ashui.css.CssValue;
import ashui.css.Identity;
import ashui.draw.DrawContext;
import ashui.draw.Path;
import ashui.draw.Stroke;
import ashui.input.Interaction;
import ashui.layout.Element;
import ashui.layout.IntoReactive;
import ashui.layout.IntoReactive.ReactiveType;
import ashui.reactive.Computed;
import ashui.reactive.Owner;
import ashui.reactive.Signal;
import ashui.reactive.Watch;
import ashui.types.Brush;
import ashui.types.Style;
import ashui.ui.Canvas;
import ashui.ui.Component;
import ashui.ui.Div;
import ashui.ui.For;
import ashui.ui.Text;

/** A named data series with one value per label. `color` accepts any CSS color and defaults to the next palette entry, `--chart-1` through `--chart-5`. **/
typedef ChartSeries = {name:String, values:Array<Float>, ?color:String};

/** Interpolation between line chart values. **/
enum abstract ChartCurve(Int) {
	/** Straight segments between values. **/
	var Linear;

	/** Smooth interpolation without overshooting the values. **/
	var Smooth;

	/** Horizontal segments with a step at each value. **/
	var Step;
}

/** A highlighted value range across a chart, such as a performance budget. **/
typedef ChartBand = {from:Float, to:Float, ?color:String, ?label:String};

/** A reference line at a specific value. **/
typedef ChartMarker = {value:Float, ?label:String, ?color:String};

typedef ChartProps = {
	/** Data series with one value per label. Reactive updates animate to the new values. **/
	series:IntoReactive<Array<ChartSeries>>,
	/** Category labels. Defaults to numeric indices. **/
	?labels:IntoReactive<Array<String>>,
	/** Chart height including axes. Defaults to 200 layout units; width follows layout. **/
	?height:Float,
	/** Line interpolation. Defaults to smooth. **/
	?curve:ChartCurve,
	/** Shows a dot at each line value. **/
	?dots:Bool,
	/** Stacks series within a bar or area. **/
	?stacked:Bool,
	/** Draws horizontal bars with category labels on the side. **/
	?horizontal:Bool,
	/** Shows grid lines at value-axis ticks. Defaults to true. **/
	?grid:Bool,
	/** Shows category labels and value-axis ticks. Defaults to true. **/
	?axes:Bool,
	/** Shows series names and colors below the plot. Defaults to true for multiple series. **/
	?legend:Bool,
	/** Shows values for the category under the pointer. Defaults to true. **/
	?tooltip:Bool,
	/** Formats axis and tooltip values. Defaults to compact numbers such as `12.5k`. **/
	?format:Float->String,
	/** Minimum value-axis bound. Defaults to the data range, or zero for area and bar charts; `max` sets the upper bound. **/
	?min:Float,
	?max:Float,
	?id:String
}

/**
	A line chart with animated data updates and hover tooltips.
	Lines use smooth interpolation by default, with category labels below
	and value-axis ticks beside the plot.

	CSS: `.ui-chart`, `.ui-chart-plot`, `.ui-chart-axis`, `.ui-chart-tooltip`
	and its rows, `.ui-chart-legend`, and `.ui-chart-swatch`. Series colors
	use `.ui-chart-c1` through `.ui-chart-c5` from `--chart-1` through
	`--chart-5`. The `color` of `.ui-chart-grid` and `.ui-chart-cursor`
	controls grid and cursor lines.
**/
class LineChart extends Component<ChartProps> {
	function render():Element
		return ChartPlot.make(Lines(false), props);
}

/** A line chart filled down to the axis with a fading area. Set `stacked` to stack series. **/
class AreaChart extends Component<ChartProps> {
	function render():Element
		return ChartPlot.make(Lines(true), props);
}

/** A bar chart with rounded ends. Series appear side by side, or stack when `stacked` is true. **/
class BarChart extends Component<ChartProps> {
	function render():Element
		return ChartPlot.make(Bars, props);
}

typedef SparklineProps = {
	values:IntoReactive<Array<Float>>,
	/** Any CSS color. Defaults to the first palette color. **/
	?color:String,
	/** Fills the area down to the lowest value with a fade. **/
	?filled:Bool,
	?curve:ChartCurve,
	/** Sparkline width in layout units. Defaults to 100; height defaults to 24. **/
	?width:Float,
	?height:Float,
	?id:String
}

/** A compact line chart for showing a trend alongside text. **/
class Sparkline extends Component<SparklineProps> {
	function render():Element {
		var values = props.values;
		return ChartPlot.make(Lines(props.filled == true), {
			series: Derived(Computed.make(() -> ([{name: "", values: ChartPlot.read(values), color: props.color}] : Array<ChartSeries>))),
			height: props.height != null ? props.height : 24,
			curve: props.curve,
			grid: false,
			axes: false,
			legend: false,
			tooltip: false,
			id: props.id
		}, {bare: true, width: props.width != null ? props.width : 100});
	}
}

typedef ThresholdChartProps = {
	values:IntoReactive<Array<Float>>,
	?labels:IntoReactive<Array<String>>,
	/** Value bands behind the line. Each data point uses the color of its containing band. **/
	?bands:Array<ChartBand>,
	/** Reference value shown as a dashed line, such as a target. **/
	?baseline:Float,
	?height:Float,
	?format:Float->String,
	?id:String
}

/** A line chart with threshold bands and points colored by their band. Useful for values such as frame times against a budget. **/
class ThresholdChart extends Component<ThresholdChartProps> {
	function render():Element {
		var values = props.values;
		return ChartPlot.make(Lines(false), {
			series: Derived(Computed.make(() -> ([{name: "Value", values: ChartPlot.read(values)}] : Array<ChartSeries>))),
			labels: props.labels,
			height: props.height,
			curve: Linear,
			dots: true,
			legend: false,
			format: props.format,
			id: props.id
		}, {bands: props.bands, markers: props.baseline == null ? null : [{value: props.baseline, label: null}], dotsByBand: true});
	}
}

typedef HistogramProps = {
	/** Values to count into histogram bins. **/
	values:IntoReactive<Array<Float>>,
	/** Number of histogram bins. Defaults to 20. **/
	?bins:Int,
	/** Reference lines across the histogram, such as a noise floor. **/
	?markers:Array<ChartMarker>,
	/** Uses a logarithmic count axis to show long-tail distributions. **/
	?logScale:Bool,
	?color:String,
	?height:Float,
	?format:Float->String,
	?id:String
}

/** A histogram with equal-width bins, labeled by the start of each bin. **/
class Histogram extends Component<HistogramProps> {
	function render():Element {
		var values = props.values, bins = props.bins != null ? props.bins : 20, log = props.logScale == true;
		var format = props.format != null ? props.format : ChartPlot.compact;
		var binned = Computed.make(() -> ChartPlot.bin(ChartPlot.read(values), bins));
		return ChartPlot.make(Bars, {
			series: Derived(Computed.make(() -> ([{
				name: "Count",
				values: [for (c in binned.get().counts) log ? Math.log(1 + c) / Math.log(10) : c],
				color: props.color
			}] : Array<ChartSeries>))),
			labels: Derived(Computed.make(() -> ([for (e in binned.get().starts) format(e)] : Array<String>))),
			height: props.height,
			legend: false,
			format: log ? v -> ChartPlot.compact(Math.round(Math.pow(10, v) - 1)) : ChartPlot.compact,
			id: props.id
		}, {
			gap: 1,
			categoryMarkers: props.markers == null ? null : Computed.make(() -> ([
				for (m in props.markers) {
					var b = binned.get();
					{at: b.width > 0 ? (m.value - b.lo) / (b.width * b.counts.length) : 0, label: m.label, color: m.color}
				}
			] : Array<{at:Float, label:Null<String>, color:Null<String>}>))
		});
	}
}

typedef ComparisonItem = {label:String, baseline:Float, current:Float};

typedef ComparisonChartProps = {
	items:IntoReactive<Array<ComparisonItem>>,
	/** Allowed percentage increase over the baseline before marking a change as bad. Defaults to 10. **/
	?threshold:Float,
	?height:Float,
	?format:Float->String,
	?id:String
}

/**
	Compares baseline and current values with paired horizontal bars. Changes
	are red above the allowed increase, or green when the value decreases.
**/
class ComparisonChart extends Component<ComparisonChartProps> {
	function render():Element {
		var items = props.items, threshold = props.threshold != null ? props.threshold : 10.0;
		var list = Computed.make(() -> (ChartPlot.read(items) : Array<ComparisonItem>));
		return ChartPlot.make(Bars, {
			series: Derived(Computed.make(() -> ([
				{name: "Baseline", values: [for (i in list.get()) i.baseline], color: "var(--chart-baseline)"},
				{name: "Current", values: [for (i in list.get()) i.current]}
			] : Array<ChartSeries>))),
			labels: Derived(Computed.make(() -> ([for (i in list.get()) i.label] : Array<String>))),
			horizontal: true,
			height: props.height,
			format: props.format,
			id: props.id
		}, {
			annotate: i -> {
				var item = list.get()[i];
				if (item == null || item.baseline == 0)
					return null;
				var change = (item.current - item.baseline) / Math.abs(item.baseline) * 100;
				var text = (change >= 0 ? "+" : "") + Std.string(Math.round(change * 10) / 10) + "%";
				{text: text, tone: change > threshold ? "bad" : change < 0 ? "good" : null};
			}
		});
	}
}

/** A labeled pie slice. `color` accepts any CSS color and defaults to the next palette entry. **/
typedef PieSlice = {label:String, value:Float, ?color:String};

typedef PieChartProps = {
	/** Slices sized by their share of the total. Reactive changes animate to the new values. **/
	slices:IntoReactive<Array<PieSlice>>,
	/** Donut hole as a fraction of the radius, from 0 to 0.9. Defaults to no hole. **/
	?donut:Float,
	/** Caption below the total in the donut hole, such as "Visitors". Requires `donut`. **/
	?total:String,
	/** Pie diameter in layout units. Defaults to 220. **/
	?height:Float,
	/** Shows slice colors and labels beside the pie. Defaults to true. **/
	?legend:Bool,
	/** Pulls out the hovered slice and shows its label, value, and percentage. Defaults to true. **/
	?tooltip:Bool,
	?format:Float->String,
	?id:String
}

/**
	A pie chart with animated slices, arranged clockwise from the top.
	Set `donut` to add a center hole and `total` for a caption below the total.
	Hovering pulls out a slice and shows its value and percentage. Slices
	animate on entry and value changes. Uses the `LineChart` CSS parts, plus
	`.ui-chart-pie-total` and `.ui-chart-pie-caption` in the center.
**/
class PieChart extends Component<PieChartProps> {
	/** Value transition duration in seconds. **/
	static inline var TRANSITION = 0.7;

	/** Hovered slice offset in layout units. **/
	static inline var PULL = 6.0;

	function render():Element {
		var slicesIn = props.slices;
		var slices = Computed.make(() -> (ChartPlot.read(slicesIn) : Array<PieSlice>));
		var format = props.format != null ? props.format : ChartPlot.compact;
		var size = props.height != null ? props.height : 220.0;
		var hole = props.donut != null ? Math.max(0, Math.min(0.9, props.donut)) : 0.0;
		var hover = Signal.make(-1);

		// Shares move from the ones shown to the new ones; the first time, from nothing, so the pie sweeps in.
		var from:Array<Float> = [], to:Array<Float> = [];
		var progress = Signal.make(1.0);
		var alive = true, running = false;
		Owner.onCleanup(() -> alive = false);
		function shares(list:Array<PieSlice>):Array<Float> {
			var total = 0.0;
			for (s in list)
				total += Math.max(0, s.value);
			return [for (s in list) total > 0 ? Math.max(0, s.value) / total : 0];
		}
		function shown(p:Float):Array<Float> {
			var t = 1 - Math.pow(1 - p, 3);
			return [for (i in 0...to.length) (i < from.length ? from[i] : 0.0) + (to[i] - (i < from.length ? from[i] : 0.0)) * t];
		}
		new Watch(() -> slices.get(), list -> {
			from = to.length == 0 ? [] : shown(progress.get());
			to = shares(list);
			progress.set(0);
			if (running)
				return;
			running = true;
			ashui.animation.AnimationScheduler.main.addTicker(dt -> {
				if (!alive) {
					running = false;
					return false;
				}
				var p = Math.min(1, progress.get() + dt / TRANSITION);
				progress.set(p);
				if (p >= 1)
					running = false;
				return p < 1;
			});
		});

		// Colours, read back from each legend swatch, palette class or its own colour, again when it is restyled.
		var swatches:Array<Null<ashui.css.Identity>> = [];
		var inks = Signal.make(0);
		function ink(i:Int):{rgb:Int, alpha:Float} {
			var s = slices.get()[i];
			var identity = i < swatches.length ? swatches[i] : null;
			var text = s != null && s.color != null ? (identity != null ? Css.resolve(identity, s.color) : s.color) : identity == null ? null : Css.resolved(identity,
				"color");
			if (text == null || text == "")
				return {rgb: 0x888888, alpha: 1.0};
			return switch (try CssValue.color(text) catch (_:Dynamic) CurrentColor) {
				case Rgba(rgb, a): {rgb: rgb, alpha: a};
				case CurrentColor: {rgb: 0x888888, alpha: 1.0};
			}
		}
		var surface = Library.part("ui-chart-surface");
		var surfaceIdentity = Identity.of(surface.tree, surface.node.id);
		var restyled:Identity->Void = identity -> if (identity == surfaceIdentity || swatches.indexOf(identity) >= 0)
			inks.set(inks.get() + 1);
		Css.restyled.push(restyled);
		Owner.onCleanup(() -> Css.restyled.remove(restyled));
		function swatch(i:Int):Div {
			var s = slices.get()[i];
			var own = s == null ? null : s.color;
			if (own == null)
				return Library.part("ui-chart-swatch", null, null, null, null, ['ui-chart-c${i % 5 + 1}']);
			var box:Null<Div> = null;
			box = new Div({classes: ["ui-chart-swatch"], bg: Computed.make(() -> {
				inks.get();
				var c = box == null ? {rgb: 0x888888, alpha: 1.0} : ink(i);
				Brush.solid(c.rgb, c.alpha);
			})});
			return box;
		}

		/** Returns slice start and end angles, clockwise from the top in radians. **/
		function angles(list:Array<Float>):Array<{start:Float, end:Float}> {
			var at = -Math.PI / 2, out = [];
			for (share in list) {
				out.push({start: at, end: at + share * Math.PI * 2});
				at += share * Math.PI * 2;
			}
			return out;
		}

		var canvas:Null<Canvas> = null;
		function draw(ctx:DrawContext) {
			inks.get();
			var w = ctx.width, h = ctx.height;
			var cx = w / 2, cy = h / 2, r = Math.min(w, h) / 2 - PULL - 2;
			if (r <= 0)
				return;
			var at = hover.get();
			var sweep = angles(shown(progress.get()));
			var gap = switch (try CssValue.color(Css.resolved(surfaceIdentity, "color")) catch (_:Dynamic) CurrentColor) {
				case Rgba(rgb, a): {rgb: rgb, alpha: a};
				case CurrentColor: {rgb: 0xffffff, alpha: 1.0};
			};
			for (i => a in sweep) {
				if (a.end - a.start <= 0)
					continue;
				var c = ink(i);
				var mid = (a.start + a.end) / 2, pull = i == at ? PULL : 0.0;
				var ox = cx + Math.cos(mid) * pull, oy = cy + Math.sin(mid) * pull;
				var path = new Path();
				if (hole > 0) {
					path.arc(ox, oy, r, a.start, a.end);
					path.arc(ox, oy, r * hole, a.end, a.start, true);
				} else {
					path.moveTo(ox, oy);
					path.arc(ox, oy, r, a.start, a.end);
				}
				path.close();
				ctx.fillPath(path, Brush.solid(c.rgb, c.alpha));
				// Drawn apart by the surface's colour along their edges.
				if (sweep.length > 1)
					ctx.strokePath(path, new Stroke(2, null, Round), Brush.solid(gap.rgb, gap.alpha));
			}
		}
		canvas = new Canvas({draw: draw});
		canvas.node.set(ashui.layout.Prop.Width, (size : Single));
		canvas.node.set(ashui.layout.Prop.Height, (size : Single));

		// The slice under the pointer: inside the ring, by its angle.
		var holder = Library.part("ui-chart-plot", null, null, [canvas, surface]);
		holder.node.set(ashui.layout.Prop.Width, (size : Single));
		holder.node.set(ashui.layout.Prop.Height, (size : Single));
		if (props.tooltip != false) {
			var interaction = Interaction.of(holder.node);
			interaction.onPointerMove(e -> {
				var dx = e.localX - size / 2, dy = e.localY - size / 2, d = Math.sqrt(dx * dx + dy * dy);
				var r = size / 2 - PULL - 2;
				var i = -1;
				if (d <= r + PULL && d >= r * hole) {
					var angle = Math.atan2(dy, dx);
					if (angle < -Math.PI / 2)
						angle += Math.PI * 2;
					for (k => a in angles(to))
						if (angle >= a.start && angle < a.end)
							i = k;
				}
				if (hover.get() != i)
					hover.set(i);
			});
			interaction.onPointerLeave(_ -> hover.set(-1));
		}
		var overlays:Array<Element> = [];
		if (hole > 0 && props.total != null) {
			var label = props.total;
			var middle = new Div({
				position: Position.Absolute,
				left: 0,
				top: 0,
				width: size,
				height: size,
				flexDirection: FlexDirection.Column,
				alignItems: Align.Center,
				justifyContent: Justify.Center
			}, [
				Library.part("ui-chart-pie-total", null, null, [new Text(Computed.make(() -> {
					var total = 0.0;
					for (s in slices.get())
						total += Math.max(0, s.value);
					format(total);
				}))]),
				Library.part("ui-chart-pie-caption", null, null, [new Text(label)])
			]);
			holder.tree.setPassThrough(middle.node.id, true);
			holder.appendChild(middle);
		}
		if (props.tooltip != false) {
			var tip = Library.part("ui-chart-tooltip", null, null, [
				Library.part("ui-chart-tooltip-row", null, null, [
					Library.part("ui-chart-tooltip-name", null, null, [new Text(Computed.make(() -> {
						var s = slices.get()[hover.get()];
						s == null ? "" : s.label;
					}))]),
					Library.part("ui-chart-tooltip-value", null, null, [new Text(Computed.make(() -> {
						var s = slices.get()[hover.get()];
						var share = hover.get() >= 0 && hover.get() < to.length ? to[hover.get()] : 0.0;
						s == null ? "" : format(s.value) + " · " + Math.round(share * 100) + "%";
					}))])
				])
			]);
			var place = new Div({
				position: Position.Absolute,
				left: Computed.make(() -> {
					var a = angles(to)[hover.get()];
					a == null ? (0 : Single) : ((size / 2 + Math.cos((a.start + a.end) / 2) * size * 0.32 - 40 : Float) : Single);
				}),
				top: Computed.make(() -> {
					var a = angles(to)[hover.get()];
					a == null ? (0 : Single) : ((size / 2 + Math.sin((a.start + a.end) / 2) * size * 0.32 - 16 : Float) : Single);
				}),
				display: Computed.make(() -> hover.get() >= 0 ? Display.Flex : Display.None)
			}, [tip]);
			holder.tree.setPassThrough(place.node.id, true);
			holder.appendChild(place);
		}
		var legend = Library.part("ui-chart-legend", null, ["hidden" => (props.legend == false ? "" : null : Null<String>)], [
			new For(() -> [for (i in 0...slices.get().length) i], i -> {
				var box = swatch(i);
				swatches[i] = Identity.of(box.tree, box.node.id);
				Owner.onCleanup(() -> if (swatches[i] == Identity.of(box.tree, box.node.id)) swatches[i] = null);
				inks.set(inks.get() + 1);
				Library.part("ui-chart-legend-item", null, null, [box, new Text(Computed.make(() -> slices.get()[i] == null ? "" : slices.get()[i].label))]);
			})
		]);
		return Library.part("ui-chart", null, ["kind" => "pie"], [holder, legend], props.id);
	}
}

/** Shape used to draw chart data. **/
enum ChartMark {
	/** Lines, with an optional fill down to the axis. **/
	Lines(area:Bool);

	Bars;
}

/** Optional plot features used by specific chart types. **/
typedef ChartExtras = {
	?bare:Bool,
	?width:Float,
	?bands:Array<ChartBand>,
	?markers:Array<ChartMarker>,
	?categoryMarkers:Computed<Array<{at:Float, label:Null<String>, color:Null<String>}>>,
	?dotsByBand:Bool,
	?gap:Float,
	?annotate:Int->Null<{text:String, tone:Null<String>}>
}

/** Plot dimensions, value range and ticks, and the rectangle used to draw data. **/
typedef ChartGeometry = {w:Float, h:Float, lo:Float, hi:Float, ticks:Array<Float>, x0:Float, y0:Float, x1:Float, y1:Float};

/** Histogram counts and bin starts, with the minimum value and bin width. **/
typedef Binned = {counts:Array<Float>, starts:Array<Float>, lo:Float, width:Float};

/**
	Shared chart renderer: a canvas for data and grid lines, with element-based
	axes, tooltip, and legend. The value axis runs upward, or rightward for
	horizontal charts. Categories occupy equal slots; line points use slot centers.
**/
class ChartPlot {
	/** Number of palette colors, from `--chart-1` through `--chart-5`. **/
	static inline var PALETTE = 5;

	/** Value transition duration in seconds. **/
	static inline var TRANSITION = 0.6;

	/** Space for labels below the plot and the top value-axis tick. **/
	static inline var BOTTOM = 24.0;

	static inline var TOP = 8.0;

	/** Estimated axis character width used to reserve label space. **/
	static inline var CHAR = 6.6;

	public static function make(mark:ChartMark, props:ChartProps, ?extras:ChartExtras):Element {
		if (extras == null)
			extras = {};
		var bars = mark.match(Bars);
		var area = switch mark {
			case Lines(a): a;
			case Bars: false;
		};
		var horizontal = bars && props.horizontal == true;
		var stacked = props.stacked == true;
		var bare = extras.bare == true;
		var showGrid = props.grid != false && !bare, showAxes = props.axes != false && !bare;
		var showTooltip = props.tooltip != false && !bare;
		var format = props.format != null ? props.format : compact;
		var height = props.height != null ? props.height : 200.0;
		var curve = props.curve != null ? props.curve : Smooth;
		var seriesIn = props.series, labelsIn = props.labels;
		var series = Computed.make(() -> (read(seriesIn) : Array<ChartSeries>));
		var count = Computed.make(() -> {
			var n = 0;
			for (s in series.get())
				n = Std.int(Math.max(n, s.values.length));
			n;
		});
		var labels = Computed.make(() -> (labelsIn == null ? [for (i in 0...count.get()) Std.string(i + 1)] : read(labelsIn) : Array<String>));

		// What is drawn moves from the values shown to the new ones: `from` and `to` per series, `progress` along the way.
		var from:Array<Array<Float>> = [], to:Array<Array<Float>> = [];
		var progress = Signal.make(1.0);
		var alive = true;
		Owner.onCleanup(() -> alive = false);
		var running = false;
		function shown(p:Float):Array<Array<Float>> {
			var t = 1 - Math.pow(1 - p, 3);
			return [
				for (s in 0...to.length) [
					for (i in 0...to[s].length) {
						var a = s < from.length && i < from[s].length ? from[s][i] : 0.0;
						a + (to[s][i] - a) * t;
					}
				]
			];
		}
		new Watch(() -> series.get(), list -> {
			var now = to.length == 0 ? [] : shown(progress.get());
			from = now;
			to = [for (s in list) s.values.copy()];
			progress.set(0);
			if (running)
				return;
			running = true;
			AnimationScheduler.main.addTicker(dt -> {
				if (!alive) {
					running = false;
					return false;
				}
				var p = Math.min(1, progress.get() + dt / TRANSITION);
				progress.set(p);
				if (p >= 1)
					running = false;
				return p < 1;
			});
		});
		var values = Computed.make(() -> (shown(progress.get()) : Array<Array<Float>>));

		// The value axis's range: what every series reaches, piled when stacked, from 0 for areas and bars, nice at its ends.
		var domain = Computed.make(() -> {
			var lo = Math.POSITIVE_INFINITY, hi = Math.NEGATIVE_INFINITY;
			var list = series.get();
			var n = count.get();
			if (stacked)
				for (i in 0...n) {
					var up = 0.0, down = 0.0;
					for (s in list) {
						var v = i < s.values.length ? s.values[i] : 0.0;
						if (v >= 0) up += v else down += v;
					}
					hi = Math.max(hi, up);
					lo = Math.min(lo, down);
				}
			else
				for (s in list)
					for (v in s.values) {
						lo = Math.min(lo, v);
						hi = Math.max(hi, v);
					}
			if (extras.bands != null)
				for (b in extras.bands) {
					lo = Math.min(lo, b.from);
					hi = Math.max(hi, b.to);
				}
			if (lo == Math.POSITIVE_INFINITY) {
				lo = 0;
				hi = 1;
			}
			if (area || bars) {
				lo = Math.min(lo, 0);
				hi = Math.max(hi, 0);
			}
			if (props.min != null)
				lo = props.min;
			if (props.max != null)
				hi = props.max;
			if (hi == lo)
				hi = lo + 1;
			[lo, hi];
		});

		// Colours: each series' swatch, styled by the palette's classes or its own colour, read back when it is restyled.
		var swatches:Array<Null<Identity>> = [];
		var inks = Signal.make(0);
		/** Resolves an explicit CSS color or the identity computed color. **/
		var ink:(identity:Null<Identity>, ?own:String, ?fallback:Int) -> {rgb:Int, alpha:Float} = null;
		ink = (identity:Null<Identity>, ?own:String, ?fallback:Int) -> {
			var otherwise = fallback != null ? fallback : 0x888888;
			var text = own != null ? (identity != null ? Css.resolve(identity, own) : own) : identity == null ? null : Css.resolved(identity, "color");
			if (text == null || text == "")
				return {rgb: otherwise, alpha: 1.0};
			return switch (try CssValue.color(text) catch (_:Dynamic) CurrentColor) {
				case Rgba(rgb, a): {rgb: rgb, alpha: a};
				case CurrentColor: {rgb: otherwise, alpha: 1.0};
			}
		};
		function swatch(i:Int):Div {
			var s = series.get()[i];
			var own = s == null ? null : s.color;
			if (own == null)
				return Library.part("ui-chart-swatch", null, null, null, null, ['ui-chart-c${i % PALETTE + 1}']);
			// Its own colour, which CSS cannot give it: resolved as it reads it, again when it is restyled.
			var box:Null<Div> = null;
			box = new Div({classes: ["ui-chart-swatch"], bg: Computed.make(() -> {
				inks.get();
				var c = box == null ? {rgb: 0x888888, alpha: 1.0} : ink(Identity.of(box.tree, box.node.id), own);
				Brush.solid(c.rgb, c.alpha);
			})});
			Library.use();
			return box;
		}
		var legendBox = Library.part("ui-chart-legend", null, [
			"hidden" => Computed.make(() -> ((props.legend == false || bare || (props.legend == null && series.get().length < 2)) ? "" : null : Null<String>))
		], [
			new For(() -> [for (i in 0...series.get().length) i], i -> {
				var box = swatch(i);
				swatches[i] = Identity.of(box.tree, box.node.id);
				Owner.onCleanup(() -> if (swatches[i] == Identity.of(box.tree, box.node.id)) swatches[i] = null);
				inks.set(inks.get() + 1);
				Library.part("ui-chart-legend-item", null, null, [box, new Text(Computed.make(() -> series.get()[i] == null ? "" : series.get()[i].name))]);
			})
		]);
		var gridInk = Library.part("ui-chart-grid");
		var cursorInk = Library.part("ui-chart-cursor");
		var surfaceInk = Library.part("ui-chart-surface");
		var bandInks = [for (b in (extras.bands != null ? extras.bands : [])) Library.part("ui-chart-band")];
		var watched = [Identity.of(gridInk.tree, gridInk.node.id), Identity.of(cursorInk.tree, cursorInk.node.id),
			Identity.of(surfaceInk.tree, surfaceInk.node.id)];
		var restyled:Identity->Void = identity -> if (watched.indexOf(identity) >= 0 || swatches.indexOf(identity) >= 0)
			inks.set(inks.get() + 1);
		Css.restyled.push(restyled);
		Owner.onCleanup(() -> Css.restyled.remove(restyled));
		function seriesInk(i:Int):{rgb:Int, alpha:Float} {
			var s = series.get()[i];
			var id = i < swatches.length ? swatches[i] : null;
			return ink(id, s == null ? null : s.color);
		}

		// Where things are: the plot's box inside the canvas, from its size and the room the labels take.
		var canvas:Canvas = null;
		var hover = Signal.make(-1);
		function geometry():ChartGeometry {
			var w = canvas.laidWidth(), h = canvas.laidHeight();
			var d = domain.get();
			var ticks = showAxes || showGrid ? niceTicks(d[0], d[1], Std.int(Math.max(2, (horizontal ? w : h) / (horizontal ? 80 : 44)))) : [d[0], d[1]];
			var lo = Math.min(d[0], ticks[0]), hi = Math.max(d[1], ticks[ticks.length - 1]);
			var longest = 0;
			if (horizontal)
				for (l in labels.get())
					longest = Std.int(Math.max(longest, l.length));
			else
				for (t in ticks)
					longest = Std.int(Math.max(longest, format(t).length));
			var left = showAxes ? Math.min(140, longest * CHAR + 12) : bare ? 1 : 4;
			var right = extras.annotate != null ? 52 : bare ? 1 : 8;
			var top = bare ? 2 : TOP, bottom = showAxes ? BOTTOM : bare ? 2 : 4;
			return {
				w: w, h: h, lo: lo, hi: hi, ticks: ticks,
				x0: left, y0: top, x1: Math.max(left + 1, w - right), y1: Math.max(top + 1, h - bottom)
			};
		}
		var geo:Null<Computed<ChartGeometry>> = null;
		/** Maps a value to its coordinate on the value axis. **/
		inline function valueAt(g:ChartGeometry, v:Float):Float {
			var f = (v - g.lo) / (g.hi - g.lo);
			return horizontal ? g.x0 + f * (g.x1 - g.x0) : g.y1 - f * (g.y1 - g.y0);
		}
		/** Returns the start and size of a category slot. **/
		function slot(g:ChartGeometry, i:Int, n:Int):{start:Float, size:Float} {
			var a = horizontal ? g.y0 : g.x0, b = horizontal ? g.y1 : g.x1;
			var size = n > 0 ? (b - a) / n : b - a;
			return {start: a + i * size, size: size};
		}
		/** Returns a line point coordinate: slot center, or edge-to-edge for bare plots. **/
		function pointAt(g:ChartGeometry, i:Int, n:Int):Float {
			if (bare)
				return n > 1 ? g.x0 + i / (n - 1) * (g.x1 - g.x0) : (g.x0 + g.x1) / 2;
			var s = slot(g, i, n);
			return s.start + s.size / 2;
		}

		function drawBars(ctx:DrawContext, g:ChartGeometry, n:Int, list:Array<ChartSeries>, vals:Array<Array<Float>>, zero:Float) {
			var groups = stacked ? 1 : Std.int(Math.max(1, list.length));
			for (i in 0...n) {
				var s = slot(g, i, n);
				var pad = extras.gap != null ? extras.gap / 2 : s.size * (groups > 1 ? 0.12 : 0.18);
				var inner = s.size - pad * 2;
				var gap = groups > 1 ? Math.min(4, inner * 0.08) : 0;
				var thick = Math.max(1, (inner - gap * (groups - 1)) / groups);
				var up = 0.0, down = 0.0;
				for (k in 0...list.length) {
					var v = i < vals[k].length ? vals[k][i] : 0.0;
					var base = 0.0;
					if (stacked) {
						base = v >= 0 ? up : down;
						if (v >= 0) up += v else down += v;
					}
					var a = valueAt(g, base), b = valueAt(g, base + v);
					var c = seriesInk(k);
					var along = s.start + pad + (stacked ? 0 : k * (thick + gap));
					// Rounded at the end away from the axis; in a pile, only the outermost on its side of it is.
					var last = true;
					if (stacked)
						for (j in k + 1...list.length) {
							var w = i < vals[j].length ? vals[j][i] : 0.0;
							if (w != 0 && (w >= 0) == (v >= 0))
								last = false;
						}
					var r = last ? Math.min(4, thick / 2) : 0;
					if (horizontal)
						ctx.fillPath(bar(Math.min(a, b), along, Math.abs(b - a), thick, r, b >= a ? 1 : 3), Brush.solid(c.rgb, c.alpha));
					else
						ctx.fillPath(bar(along, Math.min(a, b), thick, Math.abs(b - a), r, b <= a ? 0 : 2), Brush.solid(c.rgb, c.alpha));
				}
			}
		}

		function drawLines(ctx:DrawContext, g:ChartGeometry, n:Int, list:Array<ChartSeries>, vals:Array<Array<Float>>, at:Int) {
			var below = [for (i in 0...n) 0.0];
			var surface = ink(watched[2], null, 0xffffff);
			for (k in 0...list.length) {
				var c = seriesInk(k);
				var xs = [], ys = [], bases = [];
				for (i in 0...Std.int(Math.min(n, vals[k].length))) {
					var base = stacked ? below[i] : 0.0;
					var v = vals[k][i] + base;
					if (stacked)
						below[i] = v;
					xs.push(pointAt(g, i, n));
					ys.push(valueAt(g, v));
					bases.push(valueAt(g, Math.max(g.lo, Math.min(g.hi, base))));
				}
				if (xs.length == 0)
					continue;
				var line = new Path();
				follow(line, xs, ys, curve, true);
				if (area) {
					var fill = new Path();
					follow(fill, xs, ys, curve, true);
					// Back along the series below, or the axis.
					var rx = xs.copy(), rb = bases.copy();
					rx.reverse();
					rb.reverse();
					if (stacked && k > 0)
						follow(fill, rx, rb, curve, false);
					else {
						fill.lineTo(rx[0], rb[0]);
						fill.lineTo(rx[rx.length - 1], rb[rb.length - 1]);
					}
					fill.close();
					var top = g.y0, bottom = g.y1;
					ctx.fillPath(fill, Brush.linear(0, top, 0, bottom).stop(0, c.rgb, c.alpha * 0.38).stop(1, c.rgb, c.alpha * 0.03));
				}
				ctx.strokePath(line, new Stroke(bare ? 1.5 : 2, Round, Round), Brush.solid(c.rgb, c.alpha));
				if (props.dots == true || at >= 0)
					for (i in 0...xs.length) {
						var big = i == at;
						if (props.dots != true && !big)
							continue;
						var dot = c;
						if (extras.dotsByBand == true && extras.bands != null)
							for (b in 0...extras.bands.length) {
								var band = extras.bands[b];
								if (vals[k][i] >= band.from && vals[k][i] <= band.to)
									dot = ink(Identity.of(bandInks[b].tree, bandInks[b].node.id), band.color != null ? band.color : bandColor(b));
							}
						ctx.fillCircle(xs[i], ys[i], big ? 5 : 3.5, Brush.solid(surface.rgb, 1));
						ctx.fillCircle(xs[i], ys[i], big ? 3.5 : 2.5, Brush.solid(dot.rgb, dot.alpha));
					}
			}
		}

		function draw(ctx:DrawContext) {
			if (geo == null)
				return;
			inks.get();
			var g = geo.get();
			var n = count.get();
			var list = series.get();
			var vals = values.get();
			var at = hover.get();
			var hair = new Stroke(1);
			var dashed = new Stroke(1, null, null, 4, [3, 4]);
			var grid = ink(watched[0]);
			if (showGrid)
				for (t in g.ticks) {
					var p = valueAt(g, t);
					if (horizontal)
						ctx.line(p, g.y0, p, g.y1, dashed, Brush.solid(grid.rgb, grid.alpha));
					else
						ctx.line(g.x0, p, g.x1, p, dashed, Brush.solid(grid.rgb, grid.alpha));
				}
			if (extras.bands != null)
				for (k in 0...extras.bands.length) {
					var b = extras.bands[k];
					var c = ink(Identity.of(bandInks[k].tree, bandInks[k].node.id), b.color != null ? b.color : bandColor(k));
					var ya = valueAt(g, b.to), yb = valueAt(g, b.from);
					ctx.fillRect(g.x0, Math.min(ya, yb), g.x1 - g.x0, Math.abs(yb - ya), Brush.solid(c.rgb, c.alpha * 0.12));
				}
			// The label under the pointer: a band behind its bars, a line through its points.
			if (at >= 0 && at < n && showTooltip) {
				var cursor = ink(watched[1]);
				if (bars) {
					var s = slot(g, at, n);
					if (horizontal)
						ctx.fillRect(g.x0, s.start, g.x1 - g.x0, s.size, Brush.solid(cursor.rgb, 0.08));
					else
						ctx.fillRect(s.start, g.y0, s.size, g.y1 - g.y0, Brush.solid(cursor.rgb, 0.08));
				} else {
					var x = pointAt(g, at, n);
					ctx.line(x, g.y0, x, g.y1, hair, Brush.solid(cursor.rgb, 0.5));
				}
			}
			var zero = valueAt(g, Math.max(g.lo, Math.min(g.hi, 0)));
			if (bars)
				drawBars(ctx, g, n, list, vals, zero);
			else
				drawLines(ctx, g, n, list, vals, at);
			if (extras.markers != null)
				for (m in extras.markers) {
					var c = ink(watched[1], m.color);
					var p = valueAt(g, m.value);
					ctx.line(g.x0, p, g.x1, p, new Stroke(1.5, null, null, 4, [6, 4]), Brush.solid(c.rgb, 0.9));
				}
			if (extras.categoryMarkers != null)
				for (m in extras.categoryMarkers.get()) {
					var c = ink(watched[1], m.color);
					var x = g.x0 + Math.max(0, Math.min(1, m.at)) * (g.x1 - g.x0);
					ctx.line(x, g.y0, x, g.y1, new Stroke(1.5, null, null, 4, [6, 4]), Brush.solid(c.rgb, 0.9));
				}
		}

		canvas = new Canvas({draw: draw});
		geo = Computed.make(() -> geometry());
		canvas.node.set(ashui.layout.Prop.Position, Position.Absolute);
		canvas.node.set(ashui.layout.Prop.Left, (0 : Single));
		canvas.node.set(ashui.layout.Prop.Top, (0 : Single));
		canvas.node.set(ashui.layout.Prop.WidthPercent, (1 : Single));
		canvas.node.set(ashui.layout.Prop.HeightPercent, (1 : Single));

		var overlays:Array<Element> = [canvas];
		if (showAxes) {
			// The value axis's ticks: beside the plot, or under it when horizontal.
			overlays.push(new For(() -> geo.get().ticks, t -> {
				var label = Library.part("ui-chart-axis", null, null, [new Text(format(t))]);
				var n = label.node;
				n.set(ashui.layout.Prop.Position, Position.Absolute);
				if (horizontal) {
					n.set(ashui.layout.Prop.Left, Computed.make(() -> ((valueAt(geo.get(), t) - 30 : Float) : Single)));
					n.set(ashui.layout.Prop.Top, Computed.make(() -> ((geo.get().y1 + 6 : Float) : Single)));
					n.set(ashui.layout.Prop.Width, (60 : Single));
					n.set(ashui.layout.Prop.JustifyContent, Justify.Center);
				} else {
					n.set(ashui.layout.Prop.Left, (0 : Single));
					n.set(ashui.layout.Prop.Top, Computed.make(() -> ((valueAt(geo.get(), t) - 8 : Float) : Single)));
					n.set(ashui.layout.Prop.Width, Computed.make(() -> ((geo.get().x0 - 8 : Float) : Single)));
					n.set(ashui.layout.Prop.JustifyContent, Justify.End);
				}
				label;
			}));
			// The labels: under each slot, or beside it when horizontal; every few when they would crowd.
			overlays.push(new For(() -> [for (i in 0...labels.get().length) i], i -> {
				var label = Library.part("ui-chart-axis", null, ["hidden" => Computed.make(() -> {
					var g = geo.get(), n = labels.get().length;
					var room = slot(g, 0, n).size;
					var longest = 0;
					for (l in labels.get())
						longest = Std.int(Math.max(longest, l.length));
					var every = horizontal ? Math.ceil(16 / Math.max(1, room)) : Math.ceil((longest * CHAR + 8) / Math.max(1, room));
					(i % Std.int(Math.max(1, every)) == 0 ? null : "" : Null<String>);
				})], [new Text(Computed.make(() -> i < labels.get().length ? labels.get()[i] : ""))]);
				var n = label.node;
				n.set(ashui.layout.Prop.Position, Position.Absolute);
				if (horizontal) {
					n.set(ashui.layout.Prop.Left, (0 : Single));
					n.set(ashui.layout.Prop.Top, Computed.make(() -> {
						var s = slot(geo.get(), i, labels.get().length);
						((s.start + s.size / 2 - 8 : Float) : Single);
					}));
					n.set(ashui.layout.Prop.Width, Computed.make(() -> ((geo.get().x0 - 8 : Float) : Single)));
					n.set(ashui.layout.Prop.JustifyContent, Justify.End);
				} else {
					n.set(ashui.layout.Prop.Left, Computed.make(() -> {
						var g = geo.get();
						((pointAt(g, i, labels.get().length) - 40 : Float) : Single);
					}));
					n.set(ashui.layout.Prop.Top, Computed.make(() -> ((geo.get().y1 + 6 : Float) : Single)));
					n.set(ashui.layout.Prop.Width, (80 : Single));
					n.set(ashui.layout.Prop.JustifyContent, Justify.Center);
				}
				label;
			}));
		}
		if (extras.annotate != null) {
			var annotate = extras.annotate;
			overlays.push(new For(() -> [for (i in 0...count.get()) i], i -> {
				var note = Computed.make(() -> annotate(i));
				var label = Library.part("ui-chart-note", null, ["tone" => Computed.make(() -> (note.get() == null ? null : note.get().tone : Null<String>))],
					[new Text(Computed.make(() -> note.get() == null ? "" : note.get().text))]);
				var n = label.node;
				n.set(ashui.layout.Prop.Position, Position.Absolute);
				n.set(ashui.layout.Prop.Left, Computed.make(() -> ((geo.get().x1 + 6 : Float) : Single)));
				n.set(ashui.layout.Prop.Top, Computed.make(() -> {
					var s = slot(geo.get(), i, count.get());
					((s.start + s.size / 2 - 8 : Float) : Single);
				}));
				label;
			}));
		}
		if (extras.bands != null)
			for (k in 0...extras.bands.length) {
				var b = extras.bands[k];
				if (b.label == null)
					continue;
				var label = Library.part("ui-chart-axis", null, null, [new Text(b.label)], null, ["ui-chart-band-label"]);
				var n = label.node;
				n.set(ashui.layout.Prop.Position, Position.Absolute);
				n.set(ashui.layout.Prop.Top, Computed.make(() -> ((valueAt(geo.get(), b.to) + 2 : Float) : Single)));
				n.set(ashui.layout.Prop.Right, (10 : Single));
				overlays.push(label);
			}

		// The tooltip: the label under the pointer and each series' value there, beside the pointer, on whichever side has room.
		if (showTooltip) {
			var rows = new For(() -> [for (i in 0...series.get().length) i], k -> {
				var mark = swatch(k);
				Library.part("ui-chart-tooltip-row", null, null, [
					mark,
					Library.part("ui-chart-tooltip-name", null, null, [new Text(Computed.make(() -> series.get()[k] == null ? "" : series.get()[k].name))]),
					Library.part("ui-chart-tooltip-value", null, null, [new Text(Computed.make(() -> {
						var at = hover.get(), s = series.get()[k];
						s == null || at < 0 || at >= s.values.length ? "" : format(s.values[at]);
					}))])
				]);
			});
			var tip = Library.part("ui-chart-tooltip", null, null, [
				Library.part("ui-chart-tooltip-title", null, null, [new Text(Computed.make(() -> hover.get() >= 0 && hover.get() < labels.get().length ? labels.get()[hover.get()] : ""))]),
				rows
			]);
			var right = Computed.make(() -> {
				var g = geo.get(), at = hover.get();
				at >= 0 && (horizontal ? true : pointAt(g, at, count.get()) > g.w * 0.6);
			});
			var lead = Computed.make(() -> {
				var g = geo.get(), at = hover.get(), n = count.get();
				if (at < 0)
					0.0;
				else if (horizontal)
					Math.max(0, g.x1 - 4);
				else {
					var x = pointAt(g, at, n);
					right.get() ? 0.0 : x + 14;
				}
			});
			var trail = Computed.make(() -> {
				var g = geo.get(), at = hover.get();
				at < 0 || horizontal ? 0.0 : right.get() ? g.w - pointAt(g, at, count.get()) + 14 : 0.0;
			});
			var holder = new Div({
				position: Position.Absolute,
				left: 0,
				top: Computed.make(() -> ((horizontal ? (hover.get() < 0 ? 0 : slot(geo.get(), hover.get(), count.get()).start) : geo.get().y0 + 4 : Float) : Single)),
				width: Computed.make(() -> ((geo.get().w : Float) : Single)),
				flexDirection: FlexDirection.Row,
				justifyContent: Computed.make(() -> right.get() && !horizontal ? Justify.End : Justify.Start),
				alignItems: Align.Start,
				display: Computed.make(() -> hover.get() >= 0 ? Display.Flex : Display.None)
			}, [
				new Div({width: Computed.make(() -> ((lead.get() : Float) : Single)), flexShrink: 0}),
				tip,
				new Div({width: Computed.make(() -> ((trail.get() : Float) : Single)), flexShrink: 0})
			]);
			holder.tree.setPassThrough(holder.node.id, true);
			overlays.push(holder);
		}
		overlays = overlays.concat([gridInk, cursorInk, surfaceInk]).concat(cast bandInks);

		var plot = Library.part("ui-chart-plot", null, null, overlays);
		plot.node.set(ashui.layout.Prop.Height, (height : Single));
		if (extras.width != null)
			plot.node.set(ashui.layout.Prop.Width, (extras.width : Single));
		if (showTooltip) {
			var interaction = Interaction.of(plot.node);
			interaction.onPointerMove(e -> {
				var g = geo.get(), n = count.get();
				var p = horizontal ? e.localY : e.localX;
				var a:Float = horizontal ? g.y0 : g.x0, b:Float = horizontal ? g.y1 : g.x1;
				var i = p < a || p > b || n == 0 ? -1 : Std.int(Math.min(n - 1, Math.floor((p - a) / ((b - a) / n))));
				if (hover.get() != i)
					hover.set(i);
			});
			interaction.onPointerLeave(_ -> hover.set(-1));
		}
		var root = Library.part("ui-chart", null, ["bare" => (bare ? "" : null : Null<String>)], [plot, legendBox], props.id);
		if (extras.width != null)
			root.node.set(ashui.layout.Prop.Width, (extras.width : Single));
		return root;
	}

	/** Reads a constant, signal, or computed. Reactive callers subscribe to changes. **/
	public static function read<T>(v:IntoReactive<T>):T {
		return switch (v : ReactiveType<T>) {
			case Const(x): x;
			case Bound(s): s.get();
			case Derived(c): c.get();
		}
	}

	/** Formats compact numbers such as `1.2k` or `3.4M`, otherwise using at most two decimal places. **/
	public static function compact(v:Float):String {
		var a = Math.abs(v);
		inline function short(x:Float, unit:String)
			return Std.string(Math.round(x * 10) / 10) + unit;
		return a >= 1e9 ? short(v / 1e9, "B") : a >= 1e6 ? short(v / 1e6, "M") : a >= 1e4 ? short(v / 1e3, "k") : Std.string(Math.round(v * 100) / 100);
	}

	/** Returns roughly `count` round-number ticks covering the range from `lo` to `hi`. **/
	public static function niceTicks(lo:Float, hi:Float, count:Int):Array<Float> {
		var span = hi - lo;
		if (!(span > 0))
			return [lo];
		var rough = span / Math.max(1, count - 1);
		var magnitude = Math.pow(10, Math.floor(Math.log(rough) / Math.log(10)));
		var norm = rough / magnitude;
		var step = (norm < 1.5 ? 1 : norm < 3 ? 2 : norm < 7 ? 5 : 10) * magnitude;
		var start = Math.floor(lo / step + 1e-9) * step, end = Math.ceil(hi / step - 1e-9) * step;
		var out = [];
		var v = start;
		while (v <= end + step * 1e-6 && out.length < 50) {
			// Clean of the float error stepping adds.
			out.push(Math.round(v / step) * step);
			v += step;
		}
		return out;
	}

	/** Counts values into equal-width bins spanning the data minimum and maximum. **/
	public static function bin(values:Array<Float>, bins:Int):Binned {
		var lo = Math.POSITIVE_INFINITY, hi = Math.NEGATIVE_INFINITY;
		for (v in values) {
			lo = Math.min(lo, v);
			hi = Math.max(hi, v);
		}
		if (values.length == 0) {
			lo = 0;
			hi = 1;
		}
		var width = hi > lo ? (hi - lo) / bins : 1.0;
		var counts = [for (_ in 0...bins) 0.0];
		for (v in values)
			counts[Std.int(Math.min(bins - 1, Math.floor((v - lo) / width)))] += 1;
		return {counts: counts, starts: [for (i in 0...bins) lo + i * width], lo: lo, width: width};
	}

	/** Default threshold colors for good, warning, and bad regions. **/
	static function bandColor(k:Int):String
		return k == 0 ? "var(--success)" : k == 1 ? "var(--warning)" : "var(--error)";

	/** Adds interpolated segments to a path. Starts with a move when `start` is true, otherwise continues the path. **/
	static function follow(path:Path, xs:Array<Float>, ys:Array<Float>, curve:ChartCurve, start:Bool):Void {
		var n = xs.length;
		if (start)
			path.moveTo(xs[0], ys[0]);
		else
			path.lineTo(xs[0], ys[0]);
		if (n < 2)
			return;
		switch curve {
			case Linear:
				for (i in 1...n)
					path.lineTo(xs[i], ys[i]);
			case Step:
				for (i in 1...n) {
					var mid = (xs[i - 1] + xs[i]) / 2;
					path.lineTo(mid, ys[i - 1]);
					path.lineTo(mid, ys[i]);
					path.lineTo(xs[i], ys[i]);
				}
			case Smooth:
				// Monotone cubic (Fritsch and Carlson): no bump past a value that is not there.
				var d = [for (i in 0...n - 1) (ys[i + 1] - ys[i]) / (xs[i + 1] - xs[i])];
				var m = [for (i in 0...n) i == 0 ? d[0] : i == n - 1 ? d[n - 2] : d[i - 1] * d[i] <= 0 ? 0.0 : (d[i - 1] + d[i]) / 2];
				for (i in 0...n - 1) {
					if (d[i] == 0) {
						m[i] = 0;
						m[i + 1] = 0;
						continue;
					}
					var a = m[i] / d[i], b = m[i + 1] / d[i], s = a * a + b * b;
					if (s > 9) {
						var t = 3 / Math.sqrt(s);
						m[i] = t * a * d[i];
						m[i + 1] = t * b * d[i];
					}
				}
				for (i in 0...n - 1) {
					var h = (xs[i + 1] - xs[i]) / 3;
					path.cubicTo(xs[i] + h, ys[i] + m[i] * h, xs[i + 1] - h, ys[i + 1] - m[i + 1] * h, xs[i + 1], ys[i + 1]);
				}
		}
	}

	/** Creates a bar with one rounded end: 0 top, 1 right, 2 bottom, or 3 left. **/
	static function bar(x:Float, y:Float, w:Float, h:Float, r:Float, end:Int):Path {
		var p = new Path();
		r = Math.max(0, Math.min(r, end == 0 || end == 2 ? Math.min(w / 2, h) : Math.min(h / 2, w)));
		if (r <= 0 || w <= 0 || h <= 0)
			return p.rect(x, y, Math.max(0, w), Math.max(0, h));
		switch end {
			case 0:
				p.moveTo(x, y + h).lineTo(x, y + r).quadTo(x, y, x + r, y).lineTo(x + w - r, y).quadTo(x + w, y, x + w, y + r).lineTo(x + w, y + h);
			case 2:
				p.moveTo(x, y).lineTo(x + w, y).lineTo(x + w, y + h - r).quadTo(x + w, y + h, x + w - r, y + h).lineTo(x + r, y + h).quadTo(x, y + h, x, y + h - r);
			case 1:
				p.moveTo(x, y).lineTo(x + w - r, y).quadTo(x + w, y, x + w, y + r).lineTo(x + w, y + h - r).quadTo(x + w, y + h, x + w - r, y + h).lineTo(x, y + h);
			case _:
				p.moveTo(x + w, y).lineTo(x + w, y + h).lineTo(x + r, y + h).quadTo(x, y + h, x, y + h - r).lineTo(x, y + r).quadTo(x, y, x + r, y);
		}
		return p.close();
	}
}
