import ashui.core.render.Snapshot;
import ashui.css.Css;
import ashui.theme.ThemeState;
import ashui.theme.themes.DefaultTheme;
import ashui.types.Brush;
import ashui.types.Notch;
import ashui.types.Style;
import ashui.ui.Div;

/**
	Inset shadows on notched boxes: a hard ring and a soft glow, each
	without and with a border, on a concave-top dropdown, a peak, a scoop
	and a bulge. The shadow follows the notched outline, inside the border.
**/
class NotchInset {
	static final CSS = '
		.ring { box-shadow: inset 0 0 0 6px #f59e0b; }
		.glow { box-shadow: inset 0 0 14px 2px #2563eb; }
		.edged { border: 3px solid #0f172a; }
	';

	static function main() {
		ThemeState.init(DefaultTheme.bundle(), Light);
		var page = ThemeState.get().color(Background);
		var sheet = Css.load(CSS, "NotchInset.css");
		if (sheet.diagnostics.length > 0)
			Sys.println(sheet.report("NotchInset.css"));
		var dropdown:Notch = Notch.concaveTop(16, 14);
		var peak:Notch = {topLeft: 10, topRight: 10, bottomRight: 10, bottomLeft: 10, top: Peak(24, 10)};
		var scoop:Notch = {topLeft: 18, topRight: 18, bottomRight: 18, bottomLeft: 18, top: Scoop(60, 16, 6)};
		var bulge:Notch = {topLeft: 12, topRight: 12, bottomRight: 12, bottomLeft: 12, bottom: Bulge(60, 14, 5)};
		var white = Brush.solid(0xffffff);
		var build = () -> {
			var shapes = [dropdown, peak, scoop, bulge];
			function row(classes:Array<Array<String>>):Div
				return new Div({flexDirection: FlexDirection.Row, gap: 24}, [
					for (i in 0...4) new Div({notch: shapes[i], width: 130, height: 80, bg: white, classes: classes[i]})
				]);
			new Div({flexDirection: FlexDirection.Column, padding: 24, gap: 24, width: 640, height: 440}, [
				row([["ring"], ["ring"], ["ring"], ["ring"]]),
				row([["ring", "edged"], ["ring", "edged"], ["ring", "edged"], ["ring", "edged"]]),
				row([["glow"], ["glow", "edged"], ["glow"], ["glow", "edged"]])
			]);
		};
		Snapshot.scene("notch-inset@2x", 640, 440, build, page.rgb(), page.a, 2.0);
		for (p in Css.problems)
			Sys.println("css: " + p);
	}
}
