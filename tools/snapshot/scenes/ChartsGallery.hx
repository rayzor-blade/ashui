import ashui.components.Card;
import ashui.components.Chart;
import ashui.core.render.Snapshot;
import ashui.theme.ThemeState;
import ashui.theme.themes.DefaultTheme;
import ashui.types.Style;
import ashui.ui.Hxx.hxx;

/**
	Every chart, each in a card, after shadcn's chart pages: an area chart
	of two stacked series, a line chart with dots, grouped and horizontal
	bars, a pie and a donut, sparklines in a row of figures, frame times over their budgets, a
	histogram with a noise floor, and baseline against current timings.
	Writes `.ashui/snapshots/charts.png` (`charts-light` with
	`SCHEME=light`).
**/
class ChartsGallery {
	static final MONTHS = ["January", "February", "March", "April", "May", "June"];

	static function main() {
		var light = Sys.getEnv("SCHEME") == "light";
		ThemeState.init(DefaultTheme.bundle(), light ? Light : Dark);
		var page = ThemeState.get().color(Background);
		var visitors:Array<ChartSeries> = [
			{name: "Desktop", values: [186, 305, 237, 73, 209, 214]},
			{name: "Mobile", values: [80, 200, 120, 190, 130, 140]}
		];
		var traffic:Array<ChartSeries> = [
			{name: "CPU", values: [0.3, 0.45, 0.4, 0.6, 0.55, 0.7, 0.65, 0.8, 0.75, 0.9]},
			{name: "Memory", values: [0.2, 0.25, 0.3, 0.35, 0.4, 0.42, 0.45, 0.48, 0.5, 0.52]}
		];
		var frames = [12.5, 13.2, 14.8, 15.1, 14.5, 16.2, 15.8, 17.4, 18.2, 19.5, 18.8, 20.1, 22.5, 24.8, 28.2, 25.5];
		var diffs = [for (i in 0...500) i < 350 ? Math.abs(Math.sin(i * 0.01)) * 3 : i < 450 ? 3 + Math.abs(Math.cos(i * 0.05)) * 8 : 10 + Math.abs(Math.sin(i * 0.1)) * 20];
		var browsers:Array<PieSlice> = [
			{label: "Chrome", value: 275}, {label: "Safari", value: 200}, {label: "Firefox", value: 187}, {label: "Edge", value: 173},
			{label: "Other", value: 90}
		];
		var percent = (v:Float) -> Std.string(Math.round(v * 100)) + "%";
		var ms = (v:Float) -> Std.string(Math.round(v * 10) / 10) + "ms";
		var build = () -> hxx('
			<div flexDirection={Column} padding={32} gap={24} width={980}>
				<div flexDirection={Row} gap={24}>
					<card width={454}>
						<card-header><card-title>Area chart, stacked</card-title><card-description>Visitors for the last 6 months</card-description></card-header>
						<card-content><area-chart series={visitors} labels={MONTHS} stacked={true} /></card-content>
					</card>
					<card width={454}>
						<card-header><card-title>Line chart</card-title><card-description>CPU and memory, with a dot at each sample</card-description></card-header>
						<card-content><line-chart series={traffic} dots={true} format={percent} /></card-content>
					</card>
				</div>
				<div flexDirection={Row} gap={24}>
					<card width={454}>
						<card-header><card-title>Bar chart</card-title><card-description>Desktop and mobile, side by side</card-description></card-header>
						<card-content><bar-chart series={visitors} labels={MONTHS} /></card-content>
					</card>
					<card width={454}>
						<card-header><card-title>Bar chart, horizontal</card-title><card-description>Framework popularity</card-description></card-header>
						<card-content><bar-chart series={[{name: "Votes", values: [85, 65, 45, 40]}]} labels={["React", "Vue", "Svelte", "Angular"]} horizontal={true} height={180} /></card-content>
					</card>
				</div>
				<div flexDirection={Row} gap={24}>
					<card width={454}>
						<card-header><card-title>Pie chart</card-title><card-description>Browser share</card-description></card-header>
						<card-content><pie-chart slices={browsers} height={200} /></card-content>
					</card>
					<card width={454}>
						<card-header><card-title>Donut chart</card-title><card-description>Visitors by browser, the total in the middle</card-description></card-header>
						<card-content><pie-chart slices={browsers} donut={0.6} total="Visitors" height={200} /></card-content>
					</card>
				</div>
				<card>
					<card-header><card-title>Sparklines</card-title><card-description>Trends in a line of figures</card-description></card-header>
					<card-content>
						<div flexDirection={Row} gap={40} alignItems={Center}>
							<div flexDirection={Row} gap={10} alignItems={Center}><text class="text-sm text-secondary">Sales</text><sparkline values={[1.0, 2.5, 2.0, 3.5, 3.0, 4.5, 4.0, 5.0]} color="var(--success)" /><text class="text-xs text-success">+25%</text></div>
							<div flexDirection={Row} gap={10} alignItems={Center}><text class="text-sm text-secondary">Errors</text><sparkline values={[5.0, 4.0, 4.5, 3.0, 3.5, 2.0, 2.5, 1.0]} color="var(--error)" filled={true} /><text class="text-xs text-error">-60%</text></div>
							<div flexDirection={Row} gap={10} alignItems={Center}><text class="text-sm text-secondary">Latency</text><sparkline values={[45.0, 48, 42, 50, 47, 45, 43, 46]} /><text class="text-xs text-secondary">46ms</text></div>
						</div>
					</card-content>
				</card>
				<card>
					<card-header><card-title>Threshold chart</card-title><card-description>Frame times against the 60 and 30 fps budgets</card-description></card-header>
					<card-content><threshold-chart values={frames} bands={[{from: 0, to: 16.67, label: "60 fps"}, {from: 16.67, to: 33.33, label: "30 fps"}]} baseline={16.67} format={ms} height={180} /></card-content>
				</card>
				<div flexDirection={Row} gap={24}>
					<card width={454}>
						<card-header><card-title>Histogram</card-title><card-description>Pixel differences, with the noise floor</card-description></card-header>
						<card-content><histogram values={diffs} bins={30} markers={[{value: 5, label: "noise floor"}]} height={160} /></card-content>
					</card>
					<card width={454}>
						<card-header><card-title>Comparison</card-title><card-description>Baseline against current, past 10% marked</card-description></card-header>
						<card-content><comparison-chart items={[{label: "Render", baseline: 12.5, current: 14.2}, {label: "Layout", baseline: 3.2, current: 3.0}, {label: "Paint", baseline: 8.4, current: 11.8}, {label: "Composite", baseline: 2.1, current: 2.3}]} format={ms} height={180} /></card-content>
					</card>
				</div>
			</div>
		');
		Snapshot.scene(light ? "charts-light" : "charts", 980, 1940, build, page.rgb(), page.a, 2.0, 1.0);
	}
}
