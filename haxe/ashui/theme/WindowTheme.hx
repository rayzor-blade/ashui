package ashui.theme;

#if (hlwindow || ashui_window)
/**
	The scheme from a window's own appearance, which the OS reports and
	hlwindow forwards: `follow` takes it when a window opens, `handle` takes
	each `ThemeChanged` from the event loop. Preferred over
	`SystemSchemeWatcher`, which polls, wherever there is a window.
**/
class WindowTheme {
	/** The window's appearance as last reported, which `choose(null)` goes back to. **/
	static final local = new ashui.core.UiContext.Local(() -> ({system: Light, following: true} : {system:ColorScheme, following:Bool}), state -> ({system:state.system, following:state.following}));
	public static var system(get, never):ColorScheme;
	static function get_system() return local.value.system;

	/** Whether the installed theme takes the window's appearance; false while the app has `choose`n a scheme. **/
	public static var following(get, never):Bool;
	static function get_following() return local.value.following;

	/** The scheme of a window's appearance. **/
	public static function schemeOf(theme:window.Theme):ColorScheme {
		return theme == window.Theme.Dark ? Dark : Light;
	}

	/** Switches the installed theme to `window`'s current appearance, unless a scheme was chosen. **/
	public static function follow(window:window.Window):Void
		report(schemeOf(window.theme()));

	/** Switches the scheme when `event` says the appearance changed; true if it did. **/
	public static function handle(event:window.Event):Bool {
		return switch event {
			case ThemeChanged(theme):
				report(schemeOf(theme));
				true;
			case _: false;
		}
	}

	/**
		Fixes the scheme to `scheme`, which the window's appearance no longer changes; with null, goes back to the
		window's own, as it is now and as it changes. An app that lets its user pick light or dark, or the system's, calls
		this when they do.
	**/
	public static function choose(scheme:Null<ColorScheme>):Void {
		local.value.following = scheme == null;
		var state = ThemeState.tryGet();
		if (state != null)
			state.setScheme(scheme == null ? system : scheme);
	}

	static function report(scheme:ColorScheme):Void {
		local.value.system = scheme;
		var state = ThemeState.tryGet();
		if (following && state != null)
			state.setScheme(scheme);
	}
}
#end
