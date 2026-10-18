import ashui.theme.ThemeState;
import ashui.theme.WindowTheme;
import ashui.theme.themes.RestrainedTheme;
import window.Event;
import window.Theme;

/** A window's appearance sets the scheme until the app chooses one, and choosing none goes back to it. **/
class WindowThemeChoice {
	static var checks = 0;

	static function check(name:String, ok:Bool) {
		if (!ok)
			throw name;
		checks++;
		Sys.println('ok   $name');
	}

	static function main() {
		ThemeState.init(RestrainedTheme.bundle(), Light);
		var state = ThemeState.get();
		check("a window's appearance sets the scheme", WindowTheme.handle(ThemeChanged(Dark)) && state.scheme() == Dark);
		check("and is what the system is", WindowTheme.system == Dark && WindowTheme.following);
		WindowTheme.choose(Light);
		check("a chosen scheme replaces it", state.scheme() == Light && !WindowTheme.following);
		WindowTheme.handle(ThemeChanged(Light));
		WindowTheme.handle(ThemeChanged(Dark));
		check("a chosen scheme stays while the window changes", state.scheme() == Light && WindowTheme.system == Dark);
		WindowTheme.choose(null);
		check("choosing none goes back to the window's", state.scheme() == Dark && WindowTheme.following);
		WindowTheme.handle(ThemeChanged(Light));
		check("and follows it again", state.scheme() == Light);
		Sys.println('ALL PASSED ($checks checks)');
	}
}
