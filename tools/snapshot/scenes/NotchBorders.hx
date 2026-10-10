import ashui.core.render.Snapshot;
import ashui.css.Css;
import ashui.theme.ThemeState;
import ashui.theme.themes.DefaultTheme;
import ashui.types.Brush;
import ashui.types.Notch;
import ashui.types.Style;
import ashui.ui.Div;

/**
	Notched boxes with a border of four colours and widths: each stretch of
	outline takes the side it faces, a flare the top's, a bulge or a cut the
	bottom's. Beside them, the same borders on rounded boxes.
**/
class NotchBorders {
	static final CSS = '
		.sides { border-style: solid; border-width: 6px 3px 8px 2px; border-color: #dc2626 #2563eb #16a34a #f59e0b; }
		.even { border: 4px solid #0f172a; }
	';

	static function main() {
		ThemeState.init(DefaultTheme.bundle(), Light);
		var page = ThemeState.get().color(Background);
		Css.load(CSS, "NotchBorders.css");
		var dropdown:Notch = Notch.concaveTop(18, 14);
		var peak:Notch = {topLeft: 12, topRight: 12, bottomRight: 12, bottomLeft: 12, top: Peak(28, 12)};
		var bulge:Notch = {topLeft: 14, topRight: 14, bottomRight: 14, bottomLeft: 14, bottom: Bulge(60, 16, 6)};
		var cut:Notch = {topLeft: 8, topRight: 8, bottomRight: 8, bottomLeft: 8, bottom: Cut(40, 16)};
		var white = Brush.solid(0xffffff);
		var build = () -> {
			function row(classes:Array<String>):Div {
				var boxes:Array<ashui.layout.Element> = [
					for (n in [dropdown, peak, bulge, cut]) new Div({notch: n, width: 130, height: 90, bg: white, classes: classes})
				];
				boxes.push(new Div({width: 130, height: 90, bg: white, cornerRadius: ashui.types.CornerRadius.all(14), classes: classes}));
				return new Div({flexDirection: FlexDirection.Row, gap: 24}, boxes);
			}
			new Div({flexDirection: FlexDirection.Column, padding: 24, gap: 28, width: 780, height: 280}, [row(["sides"]), row(["even"])]);
		};
		Snapshot.scene("notch-borders@2x", 780, 280, build, page.rgb(), page.a, 2.0);
		for (p in Css.problems)
			Sys.println("css: " + p);
	}
}
