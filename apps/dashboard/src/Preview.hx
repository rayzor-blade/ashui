import ashui.core.render.Snapshot;
import ashui.css.CompiledCss;
import ashui.css.Css;
import ashui.theme.ThemeState;
import ashui.theme.themes.DefaultTheme;
import dashboard.Dashboard;
import dashboard.Tab;

/**
	The dashboard rendered to a PNG, to look at it while it is designed: `TAB=Media SCHEME=light`, the page and the scheme,
	`WIDTH` and `HEIGHT` its size, `CALL=1` a call under way. Run by `tools/snapshot/run.sh`.
**/
class Preview {
	static function main() {
		var light = Sys.getEnv("SCHEME") == "light";
		ThemeState.init(DefaultTheme.bundle(), light ? Light : Dark);
		Css.add(CompiledCss.file("dashboard/dashboard.css"));
		var width = Std.parseInt(Sys.getEnv("WIDTH") != null ? Sys.getEnv("WIDTH") : "1600");
		var height = Std.parseInt(Sys.getEnv("HEIGHT") != null ? Sys.getEnv("HEIGHT") : "820");
		var app = new Dashboard();
		var tab = Sys.getEnv("TAB");
		if (tab != null && tab != "")
			app.model.tab.set(Type.createEnum(Tab, tab));
		// CALL=1: the phone on a call that has run for a minute.
		if (Sys.getEnv("CALL") == "1") {
			app.phone.dial("Grace");
			app.phone.call.set(2);
			app.phone.seconds.set(67);
		}
		var page = ThemeState.get().color(Background);
		Snapshot.scene("dashboard-" + (tab == null || tab == "" ? "Vehicle" : tab) + (light ? "-light" : ""), width, height, app.build, page.rgb(), page.a, 2.0, 1.0);
	}
}
