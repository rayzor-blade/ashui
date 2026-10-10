import ashui.core.render.Snapshot;
import ashui.css.Css;
import ashui.theme.ThemeState;
import ashui.theme.themes.DefaultTheme;
import ashui.types.Style;
import ashui.ui.Div;

/**
	Clip paths by both fill rules: a pentagram drawn in one stroke, and a
	path of two squares wound the same way. By nonzero, CSS's default, the
	star's centre and the inner square are filled; by even-odd, they are holes.
**/
class ClipFillRule {
	static final CSS = '
		.box { width: 140px; height: 140px; background: linear-gradient(135deg, #2563eb, #db2777); }
		.star { clip-path: polygon(50% 0, 79% 90%, 2% 35%, 98% 35%, 21% 90%); }
		.star-eo { clip-path: polygon(evenodd, 50% 0, 79% 90%, 2% 35%, 98% 35%, 21% 90%); }
		.rings { clip-path: path("M10 10 H130 V130 H10 Z M45 45 H95 V95 H45 Z"); }
		.rings-eo { clip-path: path(evenodd, "M10 10 H130 V130 H10 Z M45 45 H95 V95 H45 Z"); }
	';

	static function main() {
		ThemeState.init(DefaultTheme.bundle(), Light);
		var page = ThemeState.get().color(Background);
		Css.load(CSS, "ClipFillRule.css");
		var build = () -> new Div({flexDirection: FlexDirection.Row, padding: 20, gap: 20, width: 680, height: 180}, [
			for (c in ["star", "star-eo", "rings", "rings-eo"]) new Div({classes: ["box", c]})
		]);
		Snapshot.scene("clip-fill-rule@2x", 680, 180, build, page.rgb(), page.a, 2.0);
		for (p in Css.problems)
			Sys.println("css: " + p);
	}
}
