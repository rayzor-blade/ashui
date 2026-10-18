package dashboard;

import ashui.app.WindowConfig;
import ashui.app.WindowedApp;
import ashui.css.CompiledCss;
import ashui.css.Css;

/** The dashboard in a window, on a desktop or in a page. **/
class Main {
	static function main() {
		Css.add(CompiledCss.file("dashboard.css"));
		// Made once the window is open and the theme has taken the window's scheme, which the 3D world is made for.
		WindowedApp.run(new WindowConfig().title("Ash Drive").size(1280, 800), () -> new Dashboard().build());
	}
}
