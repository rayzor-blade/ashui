package ashui.theme;

#if (hlwindow || ashui_window)
/**
	The scheme from a window's own appearance, which the OS reports and
	hlwindow forwards: `follow` takes it when a window opens, `handle` takes
	each `ThemeChanged` from the event loop. Preferred over
	`SystemSchemeWatcher`, which polls, wherever there is a window.
**/
class WindowTheme {
	/** The scheme of a window's appearance. **/
	public static function schemeOf(theme:window.Theme):ColorScheme {
		return theme == window.Theme.Dark ? Dark : Light;
	}

	/** Switches the installed theme to `window`'s current appearance. **/
	public static function follow(window:window.Window):Void {
		var state = ThemeState.tryGet();
		if (state != null)
			state.setScheme(schemeOf(window.theme()));
	}

	/** Switches the scheme when `event` says the appearance changed; true if it did. **/
	public static function handle(event:window.Event):Bool {
		return switch event {
			case ThemeChanged(theme):
				var state = ThemeState.tryGet();
				if (state != null)
					state.setScheme(schemeOf(theme));
				true;
			case _: false;
		}
	}
}
#end
