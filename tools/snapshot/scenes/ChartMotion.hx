import ashui.components.Chart;
import ashui.debug.MotionRecorder;
import ashui.reactive.Signal;
import ashui.theme.ThemeState;
import ashui.theme.themes.DefaultTheme;
import ashui.types.Style;
import ashui.ui.Hxx.hxx;

/**
	An area chart growing in from its axis, then the pointer over March,
	its tooltip beside it; the pointer moving on to May, the tooltip moving
	to the other side; then the data changing, the areas moving to the new
	values; then bars doing the same. Writes
	`.ashui/snapshots/motion/chart/` (`chart-light` with `SCHEME=light`;
	`PLAIN=1` leaves the overlay out).
**/
class ChartMotion {
	static final MONTHS = ["January", "February", "March", "April", "May", "June"];

	static function main() {
		var light = Sys.getEnv("SCHEME") == "light";
		var plain = Sys.getEnv("PLAIN") != null;
		ThemeState.init(DefaultTheme.bundle(), light ? Light : Dark);
		var page = ThemeState.get().color(Background);
		var data = Signal.make(([
			{name: "Desktop", values: [186.0, 305, 237, 73, 209, 214]},
			{name: "Mobile", values: [80.0, 200, 120, 190, 130, 140]}
		] : Array<ChartSeries>));
		var build = () -> hxx('
			<div padding={24} gap={24} width={520} height={560} flexDirection={Column}>
				<area-chart series={data} labels={MONTHS} stacked={true} />
				<bar-chart series={data} labels={MONTHS} />
			</div>
		');
		var result = MotionRecorder.record((light ? "chart-light" : "chart") + (plain ? "-plain" : ""), 520, 560, build, {
			fps: 60,
			frames: 150,
			minFrames: 140,
			clear: page.rgb(),
			overlay: !plain,
			thumbs: 12,
			before: (frame, tree, root) -> switch frame {
				case 50: ashui.input.Pointer.move(tree, 210, 120);
				case 70: ashui.input.Pointer.move(tree, 400, 120);
				case 90:
					ashui.input.Pointer.move(tree, 500, 540);
					data.set([
						{name: "Desktop", values: [120.0, 180, 290, 260, 150, 310]},
						{name: "Mobile", values: [140.0, 90, 160, 220, 240, 120]}
					]);
				case _:
			}
		});
		Sys.println(result.report.split("\n")[0]);
	}
}
