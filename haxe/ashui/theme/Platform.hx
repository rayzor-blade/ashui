package ashui.theme;

/** The operating system, or the browser, the program runs on. **/
enum abstract Platform(Int) {
	var MacOS;
	var Windows;
	var Linux;
	var IOS;
	var Android;
	var Web;
	var Unknown;

	/** The platform this program runs on. **/
	public static function current():Platform {
		#if js
		return Web;
		#elseif ios
		return IOS;
		#elseif android
		return Android;
		#elseif sys
		return switch Sys.systemName() {
			case "Mac": MacOS;
			case "Windows": Windows;
			case "Linux": Linux;
			case _: Unknown;
		}
		#else
		return Unknown;
		#end
	}

	/**
		Whether the system is in dark mode: macOS's `AppleInterfaceStyle`,
		Linux's `GTK_THEME` then GNOME's `color-scheme`, the browser's
		`prefers-color-scheme`. Light where it cannot tell.
	**/
	public static function detectSystemColorScheme():ColorScheme {
		#if js
		var query = js.Browser.window != null ? js.Browser.window.matchMedia("(prefers-color-scheme: dark)") : null;
		return query != null && query.matches ? Dark : Light;
		#elseif sys
		return switch current() {
			case MacOS:
				var out = run("defaults", ["read", "-g", "AppleInterfaceStyle"]);
				out != null && StringTools.trim(out).toLowerCase() == "dark" ? Dark : Light;
			case Linux:
				var gtk = Sys.getEnv("GTK_THEME");
				if (gtk != null && gtk.toLowerCase().indexOf("dark") >= 0)
					Dark;
				else {
					var out = run("gsettings", ["get", "org.gnome.desktop.interface", "color-scheme"]);
					out != null && out.indexOf("dark") >= 0 ? Dark : Light;
				}
			case _: Light;
		}
		#else
		return Light;
		#end
	}

	#if sys
	/** `command`'s standard output when it exits successfully, else null. **/
	static function run(command:String, args:Array<String>):Null<String> {
		try {
			var process = new sys.io.Process(command, args);
			var out = process.stdout.readAll().toString();
			var code = process.exitCode();
			process.close();
			return code == 0 ? out : null;
		} catch (_:Dynamic) {
			return null;
		}
	}
	#end
}
